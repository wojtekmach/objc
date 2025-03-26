Mix.install([
  {:objc, github: "wojtekmach/objc"}
  # {:objc, path: ".."}
])

defmodule Counter do
  @moduledoc """
  An overly complicated counter.

  The counter starts an ElixirKit subscriber which gets a number as a string, increments it, and
  publishes ElixirKit message. This demonstrates bidirectional communication between Elixir and
  ObjC. There could be an additional _Swift_ ElixirKit.subscribe and ElixirKit.publish which do
  the exact same things, use the same underlying NSNotification API as the transport.
  """

  def start do
    ElixirKit.subscribe(fn message ->
      IO.puts(message)
      message = message |> String.to_integer() |> then(&(&1 + 1)) |> Integer.to_string()
      Process.sleep(1000)
      ElixirKit.publish(message)
    end)

    ElixirKit.publish("0")
    Process.sleep(10000)
  end
end

defmodule ElixirKit do
  def subscribe(fun) do
    {:ok, _} = GenServer.start_link(ElixirKit.Server, fun, name: ElixirKit.Server)
  end

  def publish(message) when is_binary(message) do
    ElixirKit.NIF.publish(String.to_charlist(message))
  end
end

defmodule ElixirKit.Server do
  @moduledoc false
  use GenServer
  @impl true
  def init(fun) do
    ElixirKit.NIF.subscribe()
    {:ok, fun}
  end

  @impl true
  def handle_info({:elixirkit, message}, fun) do
    fun.(List.to_string(message))
    {:noreply, fun}
  end
end

defmodule ElixirKit.NIF do
  @moduledoc false
  use ObjC, compile: "-lobjc"

  defobjc(:subscribe, 0, ~S"""
  #import <Foundation/Foundation.h>
  static NSOperationQueue *notificationQueue = nil;
  static ERL_NIF_TERM subscribe(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
  {
      @autoreleasepool {
          if (notificationQueue == nil) {
              notificationQueue = [[NSOperationQueue alloc] init];
              [[NSNotificationCenter defaultCenter]
               addObserverForName:@"ElixirToObjC"
               object:nil
               queue:notificationQueue
               usingBlock:^(NSNotification *note) {
                   NSString *message = note.userInfo[@"message"];
                   ErlNifEnv* msg_env = enif_alloc_env();

                   // Create the message string term
                   ERL_NIF_TERM msg_term = enif_make_string(msg_env, [message UTF8String], ERL_NIF_LATIN1);

                   // Create the atom :elixirkit
                   ERL_NIF_TERM atom_term = enif_make_atom(msg_env, "elixirkit");

                   // Create the tuple {:elixirkit, message}
                   ERL_NIF_TERM tuple_term = enif_make_tuple2(msg_env, atom_term, msg_term);

                   ErlNifPid pid;
                   if (enif_whereis_pid(env, enif_make_atom(env, "Elixir.ElixirKit.Server"), &pid)) {
                       enif_send(env, &pid, msg_env, tuple_term);
                   } else {
                       NSLog(@"%@", message);
                   }
                   enif_free_env(msg_env);
               }];
          }
          return enif_make_atom(env, "ok");
      }
  }
  """)

  defobjc(:publish, 1, ~S"""
  #import <Foundation/Foundation.h>
  static ERL_NIF_TERM publish(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
  {
      char message[1024];
      enif_get_string(env, argv[0], message, sizeof(message), ERL_NIF_LATIN1);
      @autoreleasepool {
          NSString *messageStr = [NSString stringWithUTF8String:message];
          [[NSNotificationCenter defaultCenter] postNotificationName:@"ElixirToObjC"
                                                            object:nil
                                                          userInfo:@{@"message": messageStr}];
          return enif_make_atom(env, "ok");
      }
  }
  """)
end

Counter.start()
