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
        path = Path.join([unquote(Mix.Project.compile_path()), "..", "lib", "#{__MODULE__}"])
        :ok = :erlang.load_nif(path, 0)
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

  def __before_compile__(env) do
    defs = Module.get_attribute(env.module, :defs)
    opts = Module.get_attribute(env.module, :opts)

    c_src = Path.join([Mix.Project.compile_path(), "..", "c_src", "#{env.module}.m"])
    File.mkdir_p!(Path.dirname(c_src))

    so = Path.join([Mix.Project.compile_path(), "..", "lib", "#{env.module}.so"])
    File.mkdir_p!(Path.dirname(so))

    File.write!(c_src, """
    #include "erl_nif.h"

    #{Enum.map_join(defs, "\n", fn {_name, _arity, body} -> body end)}

    static ErlNifFunc nif_funcs[] =
    {
    #{Enum.map_join(defs, ", ", fn {name, arity, _} -> "{\"#{name}\", #{arity}, #{name}}" end)}
    };

    ERL_NIF_INIT(#{env.module}, nif_funcs, NULL, NULL, NULL, NULL)
    """)

    i = Path.join([:code.root_dir(), "usr", "include"])

    cc =
      case :os.type() do
        {:unix, :darwin} ->
          "clang -bundle -flat_namespace -undefined suppress"

        {:unix, :linux} ->
          "gcc -shared"
      end

    cmd = "#{cc} -o #{so} #{c_src} -I #{i} #{opts[:compile]}"
    0 = Mix.shell().cmd(cmd)
  end
end
