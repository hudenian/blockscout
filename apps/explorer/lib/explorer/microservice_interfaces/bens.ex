defmodule Explorer.MicroserviceInterfaces.BENS do
  @moduledoc """
    Interface to interact with Blockscout ENS microservice
  """

  alias Ecto.Association.NotLoaded

  alias Explorer.Chain.{
    Address,
    Address.CurrentTokenBalance,
    Block,
    InternalTransaction,
    Log,
    TokenTransfer,
    Transaction,
    Withdrawal
  }

  alias Explorer.Utility.RustService
  alias HTTPoison.Response
  require Logger

  @post_timeout :timer.seconds(5)
  @request_error_msg "Error while sending request to BENS microservice"

  @typep supported_types ::
           Address.t()
           | Block.t()
           | CurrentTokenBalance.t()
           | InternalTransaction.t()
           | Log.t()
           | TokenTransfer.t()
           | Transaction.t()
           | Withdrawal.t()

  @spec ens_names_batch_request([String.t()]) :: {:error, :disabled | String.t() | Jason.DecodeError.t()} | {:ok, any}
  def ens_names_batch_request(addresses) do
    with :ok <- RustService.check_enabled(__MODULE__) do
      body = %{
        addresses: Enum.map(addresses, &to_string/1)
      }

      http_post_request(batch_resolve_name_url(), body)
    end
  end

  def http_post_request(url, body) do
    headers = [{"Content-Type", "application/json"}]

    case HTTPoison.post(url, Jason.encode!(body), headers, recv_timeout: @post_timeout) do
      {:ok, %Response{body: body, status_code: 200}} ->
        Jason.decode(body)

      {:error, error} ->
        old_truncate = Application.get_env(:logger, :truncate)
        Logger.configure(truncate: :infinity)

        Logger.error(fn ->
          [
            "Error while sending request to BENS microservice url: #{url}, body: #{inspect(body, limit: :infinity, printable_limit: :infinity)}: ",
            inspect(error, limit: :infinity, printable_limit: :infinity)
          ]
        end)

        Logger.configure(truncate: old_truncate)
        {:error, @request_error_msg}
    end
  end

  def enabled?, do: Application.get_env(:explorer, __MODULE__)[:enabled]

  def batch_resolve_name_url do
    "#{addresses_url()}:batch-resolve-names"
  end

  def addresses_url do
    chain_id = Application.get_env(:block_scout_web, :chain_id)
    "#{RustService.base_url(__MODULE__)}/api/v1/#{chain_id}/addresses"
  end

  @spec maybe_preload_ens([supported_types]) :: [supported_types]
  def maybe_preload_ens(entity_list) do
    if enabled?() do
      apply(&preload_ens_to_list/1, [entity_list])
    else
      entity_list
    end
  end

  @spec preload_ens_to_list([supported_types]) :: [supported_types]
  def preload_ens_to_list(items) do
    address_hash_strings =
      Enum.reduce(items, [], fn item, acc ->
        acc ++ item_to_address_hash_strings(item)
      end)

    case ens_names_batch_request(address_hash_strings) do
      {:ok, result} ->
        put_ens_names(result["names"], items)

      _ ->
        items
    end
  end

  defp item_to_address_hash_strings(%Transaction{
         to_address_hash: nil,
         created_contract_address_hash: created_contract_address_hash,
         from_address_hash: from_address_hash
       }) do
    [to_string(created_contract_address_hash), to_string(from_address_hash)]
  end

  defp item_to_address_hash_strings(%Transaction{
         to_address_hash: to_address_hash,
         created_contract_address_hash: nil,
         from_address_hash: from_address_hash
       }) do
    [to_string(to_address_hash), to_string(from_address_hash)]
  end

  defp item_to_address_hash_strings(%TokenTransfer{
         to_address_hash: to_address_hash,
         from_address_hash: from_address_hash
       }) do
    [to_string(to_address_hash), to_string(from_address_hash)]
  end

  defp item_to_address_hash_strings(%InternalTransaction{
         to_address_hash: to_address_hash,
         from_address_hash: from_address_hash
       }) do
    [to_string(to_address_hash), to_string(from_address_hash)]
  end

  defp item_to_address_hash_strings(%Log{address_hash: address_hash}) do
    [to_string(address_hash)]
  end

  defp item_to_address_hash_strings(%Withdrawal{address_hash: address_hash}) do
    [to_string(address_hash)]
  end

  defp item_to_address_hash_strings(%Block{miner_hash: miner_hash}) do
    [to_string(miner_hash)]
  end

  defp item_to_address_hash_strings(%CurrentTokenBalance{address_hash: address_hash}) do
    [to_string(address_hash)]
  end

  defp put_ens_names(names, items) do
    Enum.map(items, &put_ens_name_to_item(&1, names))
  end

  defp put_ens_name_to_item(
         %Transaction{
           to_address_hash: to_address_hash,
           created_contract_address_hash: created_contract_address_hash,
           from_address_hash: from_address_hash
         } = tx,
         names
       ) do
    %Transaction{
      tx
      | to_address: alter_address(tx.to_address, to_address_hash, names),
        created_contract_address: alter_address(tx.created_contract_address, created_contract_address_hash, names),
        from_address: alter_address(tx.from_address, from_address_hash, names)
    }
  end

  defp put_ens_name_to_item(
         %TokenTransfer{
           to_address_hash: to_address_hash,
           from_address_hash: from_address_hash
         } = tt,
         names
       ) do
    %TokenTransfer{
      tt
      | to_address: alter_address(tt.to_address, to_address_hash, names),
        from_address: alter_address(tt.from_address, from_address_hash, names)
    }
  end

  defp put_ens_name_to_item(
         %InternalTransaction{
           to_address_hash: to_address_hash,
           created_contract_address_hash: created_contract_address_hash,
           from_address_hash: from_address_hash
         } = tx,
         names
       ) do
    %InternalTransaction{
      tx
      | to_address: alter_address(tx.to_address, to_address_hash, names),
        created_contract_address: alter_address(tx.created_contract_address, created_contract_address_hash, names),
        from_address: alter_address(tx.from_address, from_address_hash, names)
    }
  end

  defp put_ens_name_to_item(%Log{address_hash: address_hash} = log, names) do
    %Log{log | address: alter_address(log.address, address_hash, names)}
  end

  defp put_ens_name_to_item(%Withdrawal{address_hash: address_hash} = withdrawal, names) do
    %Withdrawal{withdrawal | address: alter_address(withdrawal.address, address_hash, names)}
  end

  defp put_ens_name_to_item(%Block{miner_hash: miner_hash} = block, names) do
    %Block{block | miner: alter_address(block.miner, miner_hash, names)}
  end

  defp put_ens_name_to_item(%CurrentTokenBalance{address_hash: address_hash} = current_token_balance, names) do
    %CurrentTokenBalance{
      current_token_balance
      | address: alter_address(current_token_balance.address, address_hash, names)
    }
  end

  defp alter_address(_, nil, _names) do
    nil
  end

  defp alter_address(%NotLoaded{}, address_hash, names) do
    %{ens_domain_name: names[to_string(address_hash)]}
  end

  defp alter_address(%Address{} = address, address_hash, names) do
    %Address{address | ens_domain_name: names[to_string(address_hash)]}
  end
end
