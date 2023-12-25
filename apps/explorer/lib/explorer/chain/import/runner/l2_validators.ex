defmodule Explorer.Chain.Import.Runner.L2Validators do

  require Ecto.Query

  alias Ecto.{Changeset, Multi, Repo}
  alias Explorer.Chain.{Import, L2Validator}
  alias Explorer.Prometheus.Instrumenter

  import Ecto.Query, only: [from: 2]

  @behaviour Import.Runner

  # milliseconds
  @timeout 60_000

  @type imported :: [L2Validator.t()]

  @impl Import.Runner
  def ecto_schema_module, do: L2Validator

  @impl Import.Runner
  def option_key, do: :l2_validators

  @impl Import.Runner
  @spec imported_table_row() :: %{:value_description => binary(), :value_type => binary()}

  @impl Import.Runner
  def imported_table_row do
    %{
      value_type: "[#{ecto_schema_module()}.t()]",
      value_description: "List of `t:#{ecto_schema_module()}.t/0`s"
    }
  end

  @impl Import.Runner
  @spec run(Multi.t(), list(), map()) :: Multi.t()
  def run(multi, changes_list, %{timestamps: timestamps} = options) do
    insert_options =
      options
      |> Map.get(option_key(), %{})
      |> Map.take(~w(on_conflict timeout)a)
      |> Map.put_new(:timeout, @timeout)
      |> Map.put(:timestamps, timestamps)

    Multi.run(multi, :insert_l2_validators, fn repo, _ ->
      Instrumenter.block_import_stage_runner(
        fn -> insert(repo, changes_list, insert_options) end,
        :block_referencing,
        :l2_validators,
        :l2_validators
      )
    end)
  end

  @impl Import.Runner
  def timeout, do: @timeout

  @spec insert(Repo.t(), [map()], %{required(:timeout) => timeout(), required(:timestamps) => Import.timestamps()}) ::
          {:ok, [Deposit.t()]}
          | {:error, [Changeset.t()]}
  def insert(repo, changes_list, %{timeout: timeout, timestamps: timestamps} = options) when is_list(changes_list) do
#    on_conflict = Map.get_lazy(options, :on_conflict, &default_on_conflict/0)

    # Enforce PolygonEdge.Deposit ShareLocks order (see docs: sharelock.md) 按rank排序
    ordered_changes_list = Enum.sort_by(changes_list, & &1.rank)

    {:ok, inserted} =
      Import.insert_changes_list(
        repo,
        ordered_changes_list,
#        conflict_target: :rank,
#        on_conflict: on_conflict,
        for: L2Validator,
        returning: true,
        timeout: timeout,
        timestamps: timestamps
      )

    {:ok, inserted}
  end

  defp default_on_conflict do
    from(
      d in L2Validator,
      update: [
        set: [
          # Don't update `msg_id` as it is a primary key and used for the conflict target
          rank: fragment("EXCLUDED.rank"), # 如果有冲突使用插入的值
          name: fragment("EXCLUDED.name"),
#          l1_transaction_hash: fragment("EXCLUDED.l1_transaction_hash"),
#          l1_timestamp: fragment("EXCLUDED.l1_timestamp"),
#          l1_block_number: fragment("EXCLUDED.l1_block_number"),
#          inserted_at: fragment("LEAST(?, EXCLUDED.inserted_at)", d.inserted_at), # LEAST返回给定的最小值 EXCLUDED.inserted_at 表示已存在的值
#          updated_at: fragment("GREATEST(?, EXCLUDED.updated_at)", d.updated_at)
        ]
      ],
      where:
        fragment(
          "(EXCLUDED.rank) IS DISTINCT FROM (?)", # IS DISTINCT FROM检查两个字段是否相等
          d.rank
        )
    )
  end
end
