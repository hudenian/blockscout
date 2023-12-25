defmodule Indexer.Fetcher.L2Validator do
  @moduledoc """
  Periodically updates tokens total_supply
  """

  use GenServer

  require Logger

  alias Explorer.{Chain, Repo}
  alias Explorer.Chain.Token
  alias Explorer.Counters.AverageBlockTime
  alias Explorer.Token.MetadataRetriever
  alias Timex.Duration

  @default_update_interval :timer.seconds(10)

  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def init(_) do
    schedule_next_update()
    {:ok, []}
  end

  def add_tokens(contract_address_hashes) do
    GenServer.cast(__MODULE__, {:add_tokens, contract_address_hashes})
  end

  def handle_cast({:add_tokens, contract_address_hashes}, state) do
    {:noreply, Enum.uniq(List.wrap(contract_address_hashes) ++ state)}
  end

  def handle_info(:update, contract_address_hashes) do

    size = [1, 2]
    li = prepare_datas(size)
    {import_data, event_name} =  {%{l2_validators: %{params: li}, timeout: :infinity}, "StateSynced"}

    case Chain.import(import_data) do
      {:ok, _} ->
        Logger.debug(fn -> "fetching l2_validator insert" end)
      {:error, reason} ->
        IO.puts("fail==========================")
        IO.puts("fail begin==========================")
#        Logger.error(
#          fn ->
#            ["failed to fetch internal transactions for blocks: ", Exception.format(:error, reason)]
#          end,
#          error_count: 1
#        )
        IO.inspect("error message #{inspect reason}")
        IO.puts("fail end==========================")
        IO.puts("fail==========================")
    end

    schedule_next_update()

    {:noreply, []}
  end

  defp schedule_next_update do
    IO.puts("==============validator====================")
    # 每3秒执行一次
    update_interval = 8000
    Process.send_after(self(), :update, update_interval)
  end

  defp update_token(nil), do: :ok

  defp update_token(address_hash_string) do
    {:ok, address_hash} = Chain.string_to_address_hash(address_hash_string)

    token = Repo.get_by(Token, contract_address_hash: address_hash)

    if token && !token.skip_metadata do
      token_params = MetadataRetriever.get_total_supply_of(address_hash_string)

      if token_params !== %{} do
        {:ok, _} = Chain.update_token(token, token_params)
      end
    end

    :ok
  end


  @spec prepare_datas(any()) :: list()
  def prepare_datas(size) do
    Enum.map(size, fn s ->
      %{
        rank: 1,
        name: "王小二",
        logo: "to"
      }
    end)
  end
end
