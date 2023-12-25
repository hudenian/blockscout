defmodule Explorer.Chain.PolygonEdge.L2Validator do
  use Explorer.Schema

  alias Explorer.Chain.{
    Hash
  }

#  @optional_attrs ~w(total_bonded total_delegation)a

  @required_attrs ~w(rank name)a
  @allowed_attrs ~w(rank name)a

#  @allowed_attrs  @required_attrs


  @type t :: %__MODULE__{
          rank: non_neg_integer(),
          name: String.t(),
          logo: String.t(),
#          commission: non_neg_integer(),
#          total_bonded: non_neg_integer(),
#          total_delegation: non_neg_integer(),
#          expect_apr: non_neg_integer(),
#          block_rate: non_neg_integer(),
#          active: non_neg_integer(),
#          auth_status: non_neg_integer(),
#          status: non_neg_integer()
        }

  @primary_key false
  schema "l2_validators" do
    field(:rank, :integer)
    field(:name, :string)
    field(:logo, :string)
#    field(:commission, :integer)
#    field(:total_bonded, :decimal)
#    field(:total_delegation, :decimal)
#    field(:expect_apr, :decimal)
#    field(:block_rate, :decimal)
#    field(:active, :integer)
#    field(:auth_status, :integer)
#    field(:status, :integer)
#
#    timestamps()
  end

#  @spec changeset(Ecto.Schema.t(), map()) :: Ecto.Schema.t()
#  def changeset(%__MODULE__{} = module, attrs \\ %{}) do
#    module
#    |> cast(attrs, @allowed_attrs)  # 确保@allowed_attrs中指定的key才会赋值到结构体中
#    |> validate_required(@required_attrs)
##    |> unique_constraint(:msg_id)
#  end

end
