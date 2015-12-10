defmodule LoggerFileBackend do
  use GenEvent

  @type path      :: String.t
  @type file      :: :file.io_device
  @type inode     :: File.Stat.t
  @type format    :: String.t
  @type level     :: Logger.level
  @type metadata  :: [atom]


  @default_format "$time $metadata[$level] $message\n"

  def init({__MODULE__, name}) do
    {:ok, configure(name, [])}
  end


  def handle_call({:configure, opts}, %{name: name}) do
    {:ok, :ok, configure(name, opts)}
  end


  def handle_call(:path, %{path: path} = state) do
    {:ok, {:ok, path}, state}
  end


  def handle_event({level, _gl, {Logger, msg, ts, md}}, %{level: min_level} = state) do
    if is_nil(min_level) or Logger.compare_levels(level, min_level) != :lt do
      log_event(level, msg, ts, md, state)
    else
      {:ok, state}
    end
  end


  # helpers

  defp log_event(_level, _msg, _ts, _md, %{path: nil} = state) do
    {:ok, state}
  end

  defp log_event(level, msg, ts, md, %{path: path, io_device: nil} = state) when is_binary(path) do
    case open_log(format_path(path, ts)) do
      {:ok, io_device, inode} ->
        log_event(level, msg, ts, md, %{state | io_device: io_device, inode: inode})
      _other ->
        {:ok, state}
    end
  end

  defp log_event(level, msg, ts, md, %{path: path, io_device: io_device, inode: inode} = state) when is_binary(path) do
    if !is_nil(inode) and inode == inode(format_path(path, ts)) do
      IO.write(io_device, format_event(level, msg, ts, md, state))
      {:ok, state}
    else
      log_event(level, msg, ts, md, %{state | io_device: nil, inode: nil})
    end
  end


  defp open_log(path) do
    case (path |> Path.dirname |> File.mkdir_p) do
      :ok ->
        case File.open(path, [:append, :utf8]) do
          {:ok, io_device} -> {:ok, io_device, inode(path)}
          other -> other
        end
      other -> other
    end
  end


  defp format_event(level, msg, ts, md, %{format: format, metadata: metadata}) do
    Logger.Formatter.format(format, level, msg, ts, Dict.take(md, metadata))
  end


  defp format_path(path_format, {{year, month, day} = date, {hour, min, sec, _} = time}) do
    # from https://github.com/SkAZi/logger_file_backend/blob/master/lib/backends/file.ex#L103
    data = %{
      date: format_date(date),
      year: pad2(year),
      month: pad2(month),
      day: pad2(day),
      time: format_time(time),
      hour: pad2(hour),
      min: pad2(min),
      sec: pad2(sec),
    }
    Enum.map(path_format |> compile, &output(&1, data))
  end

  defp format_date({y,m,d}), do: "#{y}#{pad2(m)}#{pad2(d)}"
  defp format_time({m,h,s,_}), do: "#{pad2(m)}#{pad2(h)}#{pad2(s)}"

  defp pad2(x) when x < 10, do: "0#{x}"
  defp pad2(x), do: "#{x}"

  defp output(atom, data) when is_atom(atom) do
    case data[atom] do
      nil -> ''
      val when is_binary(val) -> '#{val}'
      val -> '#{inspect val}'
    end
  end
  defp output(any, _), do: any


  defp inode(path) do
    case File.stat(path) do
      {:ok, %File.Stat{inode: inode}} -> inode
      {:error, _} -> nil
    end
  end


  def compile(str) do
    for part <- Regex.split(~r/(?<head>)\$[a-z]+(?<tail>)/, str, on: [:head, :tail], trim: true) do
      case part do
        "$" <> code -> String.to_existing_atom(code)
        _ -> part
      end
    end
  end

  defp configure(name, opts) do
    env = Application.get_env(:logger, name, [])
    opts = Keyword.merge(env, opts)
    Application.put_env(:logger, name, opts)

    level    = Keyword.get(opts, :level)
    metadata = Keyword.get(opts, :metadata, [])
    format   = Keyword.get(opts, :format, @default_format) |> Logger.Formatter.compile
    path     = Keyword.get(opts, :path)

    %{name: name, path: path, io_device: nil, inode: nil, format: format, level: level, metadata: metadata}
  end
end
