{{ config(
    schema = 'aave_v1_ethereum'
    , alias='borrow'
    , post_hook='{{ expose_spells(\'["ethereum"]\',
                                  "project",
                                  "aave_v1",
                                  \'["batwayne", "chuxinh"]\') }}'
  )
}}

{% set aave_mock_address = '0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee' %}
{% set weth_address = '0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2' %}

SELECT
      version,
      transaction_type,
      loan_type,
      erc20.symbol,
      borrow.token as token_address,
      borrower,
      repayer,
      liquidator,
      amount / concat('1e',erc20.decimals) AS amount,
      (amount/ concat('1e',p.decimals)) * price AS usd_amount,
      evt_tx_hash,
      evt_index,
      evt_block_time,
      evt_block_number   
FROM (
SELECT 
    '1' AS version,
    'borrow' AS transaction_type,
    CASE 
        WHEN _borrowRateMode = '1' THEN 'stable'
        WHEN _borrowRateMode = '2' THEN 'variable'
    END AS loan_type,
    CASE
        WHEN _reserve = '{{aave_mock_address}}' THEN '{{weth_address}}' --Using WETH instead of Aave "mock" address
        ELSE _reserve
    END AS token,
    _user AS borrower,
    NULL::string AS repayer,
    NULL::string AS liquidator,
    _amount AS amount, 
    evt_tx_hash,
    evt_index,
    evt_block_time,
    evt_block_number
FROM {{ source('aave_ethereum','LendingPool_evt_Borrow') }} 
UNION ALL 
SELECT 
    '1' AS version,
    'repay' AS transaction_type,
    NULL AS loan_type,
    CASE
        WHEN _reserve = '{{aave_mock_address}}' THEN '{{weth_address}}' --Using WETH instead of Aave "mock" address
        ELSE _reserve
    END AS token,
    _user AS borrower,
    _repayer AS repayer,
    NULL::string AS liquidator,
    - _amountMinusFees AS amount,
    evt_tx_hash,
    evt_index,
    evt_block_time,
    evt_block_number
FROM {{ source('aave_ethereum','LendingPool_evt_Repay') }}
UNION ALL
SELECT 
    '1' AS version,
    'borrow_liquidation' AS transaction_type,
    NULL AS loan_type,
    CASE
        WHEN _reserve = '{{aave_mock_address}}' THEN '{{weth_address}}' --Using WETH instead of Aave "mock" address
        ELSE _reserve
    END AS token,
    _user AS borrower,
    _liquidator AS repayer,
    _liquidator AS liquidator,
    - _purchaseAmount AS amount,
    evt_tx_hash,
    evt_index,
    evt_block_time,
    evt_block_number
FROM {{ source('aave_ethereum','LendingPool_evt_LiquidationCall') }}
) borrow
LEFT JOIN {{ ref('tokens_ethereum_erc20') }} erc20
    ON borrow.token = erc20.contract_address
LEFT JOIN {{ source('prices','usd') }} p 
    ON p.minute = date_trunc('minute', borrow.evt_block_time) 
    AND p.contract_address = borrow.token
    AND p.blockchain = 'ethereum'    
;