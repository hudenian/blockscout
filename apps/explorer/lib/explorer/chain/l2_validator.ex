defmodule Explorer.Chain.L2Validator do
  use Explorer.Schema

  @primary_key false
  schema "l2_validators" do
    field(:rank, :integer)
    field(:name, :string)
    field(:logo, :string)
#    field(:validator_hash, :bytea)
    field(:commission, :integer)
    field(:total_bonded, :decimal)
    field(:total_delegation, :decimal)
    field(:expect_apr, :decimal)
    field(:block_rate, :decimal)
    field(:active, :integer)
    field(:auth_status, :integer)
    field(:status, :integer)

    timestamps()
  end

  def get_by_rank(rank, options) do
    Chain.select_repo(options).get_by(__MODULE__, rank: 1)
  end

end
