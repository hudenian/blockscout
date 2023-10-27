defmodule BlockScoutWeb.API.V2.L2ValidatorController do
  use BlockScoutWeb, :controller

  require Logger

  import BlockScoutWeb.Chain,
    only: [
      next_page_params: 3,
      paging_options: 1,
      put_key_value_to_paging_options: 3,
      split_list_by_page: 1,
      parse_block_hash_or_number_param: 1
    ]

  import BlockScoutWeb.PagingHelper, only: [delete_parameters_from_next_page_params: 1, select_validator_status: 1]

  alias Explorer.Chain

  @transaction_necessity_by_association [
    necessity_by_association: %{
      [created_contract_address: :names] => :optional,
      [from_address: :names] => :optional,
      [to_address: :names] => :optional,
      :block => :optional,
      [created_contract_address: :smart_contract] => :optional,
      [from_address: :smart_contract] => :optional,
      [to_address: :smart_contract] => :optional
    }
  ]

  @api_true [api?: true]

  @validator_params [
    necessity_by_association: %{
      [miner: :names] => :optional,
      :uncles => :optional,
      :nephews => :optional,
      :rewards => :optional,
      :transactions => :optional,
      :withdrawals => :optional
    },
    api?: true
  ]

  action_fallback(BlockScoutWeb.API.V2.FallbackController)


  def validators(conn, params) do
    IO.inspect(params,label: "==========================call L2ValidatorController==============================")
    full_options = select_validator_status(params)

    l2_validators_plus_one =
      full_options
      |> Keyword.merge(paging_options(params))
      |> Keyword.merge(@api_true)
      |> Chain.list_l2Validators()

    {validators, next_page} = split_list_by_page(l2_validators_plus_one)

    next_page_params = next_page |> next_page_params(validators, delete_parameters_from_next_page_params(params))

    conn
    |> put_status(200)
    |> render(:l2Validators, %{validator: validators, next_page_params: next_page_params})
  end
end
