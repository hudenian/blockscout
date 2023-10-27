defmodule Explorer.Repo.Migrations.CreateL2Validators do
  use Ecto.Migration

  def change do
    create table(:l2_validators, primary_key: false) do
      add(:rank, :integer, null: false)
      add(:name, :string, null: true)
      add(:logo, :string, null: true)
      add(:validator_hash, :bytea, null: false, primary_key: true)
      add(:commission, :integer, null: true)
      add(:total_bonded, :numeric, precision: 100, null: false)
      add(:total_delegation, :numeric, precision: 100, null: false)
      add(:expect_apr, :numeric, precision: 100, null: false)
      add(:block_rate, :numeric, precision: 100, null: false)
      add(:active, :integer, null: false)
      add(:auth_status, :integer, null: true)
      add(:status, :integer, null: true)

      timestamps(null: false, type: :utc_datetime_usec)
    end
  end
end
