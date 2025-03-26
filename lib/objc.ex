defmodule ObjC do
  defmacro __using__(opts) do
    quote do
      @on_load :init_nifs
      @before_compile ObjC
      @opts unquote(opts)
      Module.register_attribute(__MODULE__, :defs, accumulate: true)
      import ObjC, only: [defobjc: 3]
      @doc false
      def init_nifs() do
        path = Path.join(ObjC.nif_path(__MODULE__), "#{__MODULE__}")
        :ok = :erlang.load_nif(String.to_charlist(path), 0)
      end
    end
  end

  defmacro defobjc(name, arity, body) do
    quote do
      @defs {unquote(name), unquote(arity), unquote(body)}
      def unquote(name)(unquote_splicing(Macro.generate_arguments(arity, nil))) do
        _ = [unquote_splicing(Macro.generate_arguments(arity, nil))]
        :erlang.nif_error("NIF library not loaded")
      end
    end
  end

  # Helper function to determine if running under Mix project or Mix.install
  def in_mix_project? do
    # If Mix.Project.get() returns nil, we're under Mix.install
    Mix.Project.get() != nil
  end

  # Helper function to determine appropriate NIF path
  def nif_path(module) do
    if in_mix_project?() do
      Path.join([Mix.Project.compile_path(), "..", "lib"])
    else
      dir = Path.join([System.tmp_dir!(), "elixir_objc", Atom.to_string(module)])
      File.mkdir_p!(dir)
      dir
    end
  end

  # Helper function to determine appropriate C source path
  def c_src_path(module) do
    if in_mix_project?() do
      path = Path.join([Mix.Project.compile_path(), "..", "c_src"])
      File.mkdir_p!(path)
      Path.join(path, "#{module}.m")
    else
      dir = Path.join([System.tmp_dir!(), "elixir_objc", Atom.to_string(module), "c_src"])
      File.mkdir_p!(dir)
      Path.join(dir, "#{module}.m")
    end
  end

  def __before_compile__(env) do
    defs = Module.get_attribute(env.module, :defs)
    opts = Module.get_attribute(env.module, :opts)

    # Get paths
    c_src = c_src_path(env.module)
    nif_dir = nif_path(env.module)
    so = Path.join(nif_dir, "#{env.module}.so")

    # Write C source file
    File.write!(c_src, """
    #include "erl_nif.h"
    #{Enum.map_join(defs, "\n", fn {_name, _arity, body} -> body end)}
    static ErlNifFunc nif_funcs[] =
    {
    #{Enum.map_join(defs, ",\n    ", fn {name, arity, _} -> "{\"#{name}\", #{arity}, #{name}}" end)}
    };
    ERL_NIF_INIT(#{env.module}, nif_funcs, NULL, NULL, NULL, NULL)
    """)

    # Find Erlang include directory
    i = Path.join([:code.root_dir(), "usr", "include"])

    # Set appropriate compiler command based on OS
    cc =
      case :os.type() do
        {:unix, :darwin} ->
          "clang -bundle -undefined dynamic_lookup -flat_namespace"

        {:unix, :linux} ->
          "gcc -shared"

        _ ->
          raise "Unsupported operating system"
      end

    # Additional compiler options
    compile_opts = opts[:compile] || ""

    # Build command
    cmd = "#{cc} -o #{so} #{c_src} -I #{i} #{compile_opts}"

    # Execute and check result
    cmd_result =
      if Code.ensure_loaded?(Mix.Shell) do
        Mix.shell().cmd(cmd)
      else
        {result, _} = System.cmd("sh", ["-c", cmd], stderr_to_stdout: true)
        IO.puts("Compiling NIF: #{cmd}")
        result
      end

    if cmd_result != 0 do
      raise "Failed to compile NIF module. Command: #{cmd}"
    end
  end
end
