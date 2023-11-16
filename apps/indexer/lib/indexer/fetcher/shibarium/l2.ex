defmodule Indexer.Fetcher.Shibarium.L2 do
  @moduledoc """
  Fills shibarium_bridge DB table.
  """

  use GenServer
  use Indexer.Fetcher

  require Logger

  import Ecto.Query

  import EthereumJSONRPC, only: [
    integer_to_quantity: 1,
    json_rpc: 2,
    quantity_to_integer: 1,
    request: 1
  ]

  import Explorer.Helper, only: [decode_data: 2, parse_integer: 1]

  alias Explorer.{Chain, Repo}
  alias Explorer.Chain.Shibarium.Bridge
  alias Indexer.Helper

  @eth_get_logs_range_size 1000
  @fetcher_name :shibarium_bridge_l2
  @empty_hash "0x0000000000000000000000000000000000000000000000000000000000000000"

  # 32-byte signature of the event TokenDeposited(address indexed rootToken, address indexed childToken, address indexed user, uint256 amount, uint256 depositCount)
  @token_deposited_event "0xec3afb067bce33c5a294470ec5b29e6759301cd3928550490c6d48816cdc2f5d"

  # 32-byte signature of the event Transfer(address indexed from, address indexed to, uint256 value)
  @transfer_event "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"

  # 32-byte signature of the event TransferSingle(address indexed operator, address indexed from, address indexed to, uint256 id, uint256 value)
  @transfer_single_event "0xc3d58168c5ae7397731d063d5bbf3d657854427343f4c083240f7aacaa2d0f62"

  # 32-byte signature of the event TransferBatch(address indexed operator, address indexed from, address indexed to, uint256[] ids, uint256[] values)
  @transfer_batch_event "0x4a39dc06d4c0dbc64b70af90fd698a233a518aa5d07e595d983b8c0526c8f7fb"

  # 32-byte signature of the event Withdraw(address indexed rootToken, address indexed from, uint256 amount, uint256, uint256)
  @withdraw_event "0xebff2602b3f468259e1e99f613fed6691f3a6526effe6ef3e768ba7ae7a36c4f"

  # 32-byte signature of the event LogFeeTransfer(address indexed, address indexed, address indexed, uint256, uint256, uint256, uint256, uint256)
  @log_fee_transfer_event "0x4dfe1bbbcf077ddc3e01291eea2d5c70c2b422b415d95645b9adcfd678cb1d63"

  def child_spec(start_link_arguments) do
    spec = %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, start_link_arguments},
      restart: :transient,
      type: :worker
    }

    Supervisor.child_spec(spec, [])
  end

  def start_link(args, gen_server_options \\ []) do
    GenServer.start_link(__MODULE__, args, Keyword.put_new(gen_server_options, :name, __MODULE__))
  end

  @impl GenServer
  def init(args) do
    json_rpc_named_arguments = args[:json_rpc_named_arguments]
    {:ok, %{}, {:continue, json_rpc_named_arguments}}
  end

  @impl GenServer
  def handle_continue(json_rpc_named_arguments, state) do
    Logger.metadata(fetcher: @fetcher_name)
    # two seconds pause needed to avoid exceeding Supervisor restart intensity when DB issues
    Process.send_after(self(), :init_with_delay, 2000)
    {:noreply, %{json_rpc_named_arguments: json_rpc_named_arguments}}
  end

  @impl GenServer
  def handle_info(:init_with_delay, %{json_rpc_named_arguments: json_rpc_named_arguments} = state) do
    env = Application.get_all_env(:indexer)[__MODULE__]

    with {:start_block_undefined, false} <- {:start_block_undefined, is_nil(env[:start_block])},
         {:child_chain_address_is_valid, true} <- {:child_chain_address_is_valid, Helper.is_address_correct?(env[:child_chain])},
         {:weth_address_is_valid, true} <- {:weth_address_is_valid, Helper.is_address_correct?(env[:weth])},
         {:bone_withdraw_address_is_valid, true} <- {:bone_withdraw_address_is_valid, Helper.is_address_correct?(env[:bone_withdraw])},
         start_block = parse_integer(env[:start_block]),
         false <- is_nil(start_block),
         true <- start_block > 0,
         {last_l2_block_number, last_l2_transaction_hash} <- get_last_l2_item(),
         {:ok, latest_block} = get_block_number_by_tag("latest", json_rpc_named_arguments),
         {:start_block_valid, true} <-
           {:start_block_valid,
            (start_block <= last_l2_block_number || last_l2_block_number == 0) && start_block <= latest_block},
         {:ok, last_l2_tx} <- get_transaction_by_hash(last_l2_transaction_hash, json_rpc_named_arguments),
         {:l2_tx_not_found, false} <- {:l2_tx_not_found, !is_nil(last_l2_transaction_hash) && is_nil(last_l2_tx)} do
      Process.send(self(), :continue, [])

      {:noreply,
       %{
         start_block: max(start_block, last_l2_block_number),
         latest_block: latest_block,
         child_chain: env[:child_chain],
         weth: env[:weth],
         bone_withdraw: env[:bone_withdraw],
         json_rpc_named_arguments: json_rpc_named_arguments
       }}
    else
      {:start_block_undefined, true} ->
        # the process shouldn't start if the start block is not defined
        {:stop, :normal, state}

      {:child_chain_address_is_valid, false} ->
        Logger.error("ChildChain contract address is invalid or not defined.")
        {:stop, :normal, state}

      {:weth_address_is_valid, false} ->
        Logger.error("WETH contract address is invalid or not defined.")
        {:stop, :normal, state}

      {:bone_withdraw_address_is_valid, false} ->
        Logger.error("Bone Withdraw contract address is invalid or not defined.")
        {:stop, :normal, state}

      {:start_block_valid, false} ->
        Logger.error("Invalid L2 Start Block value. Please, check the value and shibarium_bridge table.")
        {:stop, :normal, state}

      {:error, error_data} ->
        Logger.error("Cannot get last L2 transaction by its hash or latest block from RPC due to RPC error: #{inspect(error_data)}")

        {:stop, :normal, state}

      {:l2_tx_not_found, true} ->
        Logger.error(
          "Cannot find last L2 transaction from RPC by its hash. Probably, there was a reorg on L2 chain. Please, check shibarium_bridge table."
        )

        {:stop, :normal, state}

      _ ->
        Logger.error("L2 Start Block is invalid or zero.")
        {:stop, :normal, state}
    end
  end

  @impl GenServer
  def handle_info(
        :continue,
        %{
          start_block: start_block,
          latest_block: end_block,
          child_chain: child_chain,
          weth: weth,
          bone_withdraw: bone_withdraw,
          json_rpc_named_arguments: json_rpc_named_arguments
        } = state
      ) do
    start_block..end_block
    |> Enum.chunk_every(@eth_get_logs_range_size)
    |> Enum.each(fn current_chunk ->
      chunk_start = List.first(current_chunk)
      chunk_end = List.last(current_chunk)

      log_blocks_chunk_handling(chunk_start, chunk_end, start_block, end_block, nil, "L2")

      operations =
        {chunk_start, chunk_end}
        |> get_logs_all(child_chain, weth, bone_withdraw, json_rpc_named_arguments)
        |> prepare_operations(json_rpc_named_arguments)

      {:ok, _} =
        Chain.import(%{
          shibarium_bridge_operations: %{params: prepare_insert_items(operations)},
          timeout: :infinity
        })

      log_blocks_chunk_handling(
        chunk_start,
        chunk_end,
        start_block,
        end_block,
        "#{Enum.count(operations)} L2 operation(s)",
        "L2"
      )
    end)

    {:stop, :normal, state}
  end

  @impl GenServer
  def handle_info({ref, _result}, state) do
    Process.demonitor(ref, [:flush])
    {:noreply, state}
  end

  def reorg_handle(reorg_block) do
    {deleted_count, _} =
      Repo.delete_all(from(sb in Bridge, where: sb.l2_block_number >= ^reorg_block and is_nil(sb.l1_transaction_hash)))

    {updated_count1, _} =
      Repo.update_all(
        from(sb in Bridge,
          where:
            sb.l2_block_number >= ^reorg_block and not is_nil(sb.l1_transaction_hash) and
              sb.operation_type == "withdrawal"
        ),
        set: [timestamp: nil]
      )

    {updated_count2, _} =
      Repo.update_all(
        from(sb in Bridge, where: sb.l2_block_number >= ^reorg_block and not is_nil(sb.l1_transaction_hash)),
        set: [l2_transaction_hash: nil, l2_block_number: nil]
      )

    updated_count = max(updated_count1, updated_count2)

    if deleted_count > 0 or updated_count > 0 do
      Logger.warning(
        "As L2 reorg was detected, some rows with l2_block_number >= #{reorg_block} were affected (removed or updated) in the shibarium_bridge table. Number of removed rows: #{deleted_count}. Number of updated rows: >= #{updated_count}."
      )
    end
  end

  defp get_last_l2_item do
    query =
      from(sb in Bridge,
        select: {sb.l2_block_number, sb.l2_transaction_hash},
        where: not is_nil(sb.l2_block_number),
        order_by: [desc: sb.l2_block_number],
        limit: 1
      )

    query
    |> Repo.one()
    |> Kernel.||({0, nil})
  end

  defp get_logs_all({chunk_start, chunk_end}, child_chain, weth, bone_withdraw, json_rpc_named_arguments) do
    # todo
  end

  defp get_logs(from_block, to_block, address, topics, json_rpc_named_arguments, retries \\ 100_000_000) do
    processed_from_block = if is_integer(from_block), do: integer_to_quantity(from_block), else: from_block
    processed_to_block = if is_integer(to_block), do: integer_to_quantity(to_block), else: to_block

    req =
      request(%{
        id: 0,
        method: "eth_getLogs",
        params: [
          %{
            :fromBlock => processed_from_block,
            :toBlock => processed_to_block,
            :address => address,
            :topics => topics
          }
        ]
      })

    error_message = &"Cannot fetch logs for the block range #{from_block}..#{to_block}. Error: #{inspect(&1)}"

    repeated_call(&json_rpc/2, [req, json_rpc_named_arguments], error_message, retries)
  end

  defp get_transaction_by_hash(hash, json_rpc_named_arguments, retries_left \\ 3)

  defp get_transaction_by_hash(hash, _json_rpc_named_arguments, _retries_left) when is_nil(hash), do: {:ok, nil}

  defp get_transaction_by_hash(hash, json_rpc_named_arguments, retries) do
    req =
      request(%{
        id: 0,
        method: "eth_getTransactionByHash",
        params: [hash]
      })

    error_message = &"eth_getTransactionByHash failed. Error: #{inspect(&1)}"

    repeated_call(&json_rpc/2, [req, json_rpc_named_arguments], error_message, retries)
  end

  defp log_blocks_chunk_handling(chunk_start, chunk_end, start_block, end_block, items_count, layer) do
    is_start = is_nil(items_count)

    {type, found} =
      if is_start do
        {"Start", ""}
      else
        {"Finish", " Found #{items_count}."}
      end

    target_range =
      if chunk_start != start_block or chunk_end != end_block do
        progress =
          if is_start do
            ""
          else
            percentage =
              (chunk_end - start_block + 1)
              |> Decimal.div(end_block - start_block + 1)
              |> Decimal.mult(100)
              |> Decimal.round(2)
              |> Decimal.to_string()

            " Progress: #{percentage}%"
          end

        " Target range: #{start_block}..#{end_block}.#{progress}"
      else
        ""
      end

    if chunk_start == chunk_end do
      Logger.info("#{type} handling #{layer} block ##{chunk_start}.#{found}#{target_range}")
    else
      Logger.info("#{type} handling #{layer} block range #{chunk_start}..#{chunk_end}.#{found}#{target_range}")
    end
  end

  defp repeated_call(func, args, error_message, retries_left) do
    case apply(func, args) do
      {:ok, _} = res ->
        res

      {:error, message} = err ->
        retries_left = retries_left - 1

        if retries_left <= 0 do
          Logger.error(error_message.(message))
          err
        else
          Logger.error("#{error_message.(message)} Retrying...")
          :timer.sleep(3000)
          repeated_call(func, args, error_message, retries_left)
        end
    end
  end
end
