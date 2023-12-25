defmodule Explorer.Chain.L2Validator do
  use Explorer.Schema


  @optional_attrs ~w(logo)a

  @required_attrs ~w(rank name)a

  @allowed_attrs @optional_attrs ++ @required_attrs

  @primary_key false
  schema "l2_validators" do
    field(:rank, :integer)
    field(:name, :string)
    field(:logo, :string)
##    field(:validator_hash, :bytea)
#    field(:commission, :integer)
#    field(:total_bonded, :decimal)
#    field(:total_delegation, :decimal)
#    field(:expect_apr, :decimal)
#    field(:block_rate, :decimal)
#    field(:active, :integer)
#    field(:auth_status, :integer)
#    field(:status, :integer)
#
    timestamps()
  end

  def get_by_rank(rank, options) do
    Chain.select_repo(options).get_by(__MODULE__, rank: 1)
  end

  @spec changeset(Ecto.Schema.t(), map()) :: Ecto.Schema.t()
  def changeset(%__MODULE__{} = module, attrs \\ %{}) do
    module
    |> cast(attrs, @allowed_attrs)  # 确保@allowed_attrs中指定的key才会赋值到结构体中
    |> validate_required(@required_attrs)
    #    |> unique_constraint(:msg_id)
  end

end
