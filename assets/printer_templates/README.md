# Local receipt template

`order_receipt_v1.json` controls the order and test receipt layout. The app
validates it at startup and uses `order_receipt_fallback_v1.json` if validation
fails. These files are bundled with the app; there is no server-side template
storage or download.

Supported section types:

- `image`: bundled PNG `asset`, `widthDots`, `position`, and optional
  `spaceBeforeDots` / `spaceAfterDots`
- `text`: `field` or `template`, optional `fallback`, `prefix`, `style`, `when`
- `separator`: one-character `character`
- `moneyRow`: `label` template and numeric `amountField`
- `repeat`: `source`, `itemName`, and nested `children`
- `feed`: `lines` from 0 to 10
- `cut`: `mode` is `none` or `partial`

Supported condition operators are `notEmpty`, `empty`, `greaterThan`, `equals`,
`isTrue`, and `isFalse`. Template placeholders use `{{field.path}}`. Arbitrary
code, JavaScript, and raw printer command bytes are intentionally unsupported.

Available order fields:

- `app.name`
- `store.name`, `store.phone`, `store.address`
- `customer.displayName`
- `order.shortId`, `order.fulfillmentLabel`, `order.paymentLabel`,
  `order.dueAtLabel`, `order.itemCountLabel`, `order.hasItems`, `order.items`
- Each item: `item.quantity`, `item.name`, `item.price`, `item.isReward`,
  `item.instructions`, `item.optionLines`
- Each option line: `option.text`
- `pricing.subtotal`, `pricing.deliveryFee`, `pricing.serviceFee`, `pricing.tax`,
  `pricing.tip`, `pricing.refunded`, `pricing.hasRefund`, `pricing.total`

Available test fields:

- `app.name`, `test.message`
- `printer.name`, `printer.connectionType`, `printer.target`,
  `printer.paperSize`, `printer.protocol`
