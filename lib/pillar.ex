defmodule Pillar do
  @moduledoc """
  """
  alias Pillar.Connection
  alias Pillar.HttpClient
  alias Pillar.QueryBuilder
  alias Pillar.ResponseParser

  def query(%Connection{} = connection, query, params \\ %{}) do
    final_sql = QueryBuilder.build(query, params) <> "\n FORMAT JSON"

    connection
    |> Connection.url_from_connection()
    |> HttpClient.post(final_sql)
    |> ResponseParser.parse()
  end

  defmacro __using__(
             connection_string: connection_string,
             name: name,
             pool_size: pool_size
           ) do
    quote do
      use GenServer
      import Supervisor.Spec

      @pool_timeout_for_waiting_worker 1_000

      defp poolboy_config do
        [
          name: {:local, unquote(name)},
          worker_module: Pillar.Pool.Worker,
          size: unquote(pool_size),
          max_overflow: Kernel.ceil(unquote(pool_size) * 0.3)
        ]
      end

      def start_link(_opts \\ nil) do
        children = [
          :poolboy.child_spec(:worker, poolboy_config(), unquote(connection_string))
        ]

        opts = [strategy: :one_for_one, name: :"#{unquote(name)}.Supervisor"]
        Supervisor.start_link(children, opts)
      end

      def init(init_arg) do
        {:ok, init_arg}
      end

      def query(sql, params \\ %{}) do
        :poolboy.transaction(
          unquote(name),
          fn pid -> GenServer.call(pid, {sql, params}) end,
          @pool_timeout_for_waiting_worker
        )
      end

      def async_query(sql, params \\ %{}) do
        :poolboy.transaction(
          unquote(name),
          fn pid -> GenServer.cast(pid, {sql, params}) end,
          @pool_timeout_for_waiting_worker
        )
      end
    end
  end
end
