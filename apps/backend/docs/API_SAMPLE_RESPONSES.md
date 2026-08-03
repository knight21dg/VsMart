# VS Mart — Sample API Responses (every customer case)

_Captured as the seeded demo customer (+919000000007). Run `python manage.py seed_app` then this script to regenerate._


## System

### Health
`GET /api/v1/health` → **200**

```json
{
  "success": true,
  "message": "",
  "data": {
    "status": "ok",
    "service": "vsmart-api"
  }
}
```

### App config
`GET /api/v1/app-config` → **200**

```json
{
  "success": true,
  "message": "",
  "data": {
    "currency": "INR",
    "gstRate": 0.18,
    "deliveryFee": 45.0,
    "freeDeliveryThreshold": 499.0,
    "supportPhone": "",
    "supportEmail": "",
    "minAppVersion": "1.0.0",
    "maintenance": false,
    "featureFlags": {
      "storePricing": false,
      "maintenance": false
    }
  }
}
```

### Feature flags
`GET /api/v1/feature-flags` → **200**

```json
{
  "success": true,
  "message": "",
  "data": {
    "storePricing": false,
    "maintenance": false
  }
}
```


## Auth

### Send OTP
`POST /api/v1/auth/otp/send` → **200**

```json
{
  "success": true,
  "message": "",
  "data": {
    "verification_id": "fc826569c2dd4b1c80404a733845024e"
  }
}
```

### Current user
`GET /api/v1/users/me` → **200**

```json
{
  "success": true,
  "message": "",
  "data": {
    "id": "333",
    "phone": "+919000000007",
    "name": "Demo Shopper",
    "email": "demo@vsmart.app",
    "role": "customer",
    "avatar_url": null,
    "kyc_status": "verified",
    "credit_enabled": true,
    "created_at": "2026-06-23T13:21:28.387154+05:30"
  }
}
```


## Catalog

### Departments
`GET /api/v1/categories` → **200**

```json
{
  "success": true,
  "message": "",
  "data": [
    {
      "id": "4",
      "name": "Beverages",
      "iconName": "local_cafe",
      "imageUrl": "https://cdn.dummyjson.com/product-images/groceries/juice/thumbnail.webp",
      "productCount": 4,
      "parentId": null
    },
    {
      "id": "2",
      "name": "Dairy & Eggs",
      "iconName": "egg",
      "imageUrl": "https://cdn.dummyjson.com/product-images/groceries/milk/thumbnail.webp",
      "productCount": 3,
      "parentId": null
    },
    {
      "id": "1",
      "name": "Fruits & Vegetables",
      "iconName": "eco",
      "imageUrl": "https://cdn.dummyjson.com/product-images/groceries/apple/thumbnail.webp",
      "productCount": 9,
      "parentId": null
    },
    {
      "id": "7",
      "name": "Grocery",
      "iconName": "",
      "imageUrl": null,
      "productCount": 0,
      "parentId": null
    },
    {
      "id": "6",
      "name": "Household",
      "iconName": "cleaning_services",
      "imageUrl": "https://cdn.dummyjson.com/product-images/groceries/tissue-paper/thumbnail.webp",
      "productCount": 2,
      "parentId": null
    },
    {
      "id": "3",
      "name": "Meat & Seafood",
      "iconName": "set_meal",
      "imageUrl": "https://cdn.dummyjson.com/product-images/groceries/chicken-meat/thumbnail.webp",
      "productCount": 3,
      "parentId": null
    },
    {
      "id": "27",
     
  … (truncated)
```

### Sub-categories
`GET /api/v1/categories/4/sub-categories` → **200**

```json
{
  "success": true,
  "message": "",
  "data": [
    {
      "id": "17",
      "name": "Juices",
      "iconName": "local_cafe",
      "imageUrl": "https://cdn.dummyjson.com/product-images/groceries/juice/thumbnail.webp",
      "productCount": 1,
      "parentId": "4"
    },
    {
      "id": "18",
      "name": "Soft Drinks",
      "iconName": "local_cafe",
      "imageUrl": "https://cdn.dummyjson.com/product-images/groceries/soft-drinks/thumbnail.webp",
      "productCount": 1,
      "parentId": "4"
    },
    {
      "id": "19",
      "name": "Water",
      "iconName": "local_cafe",
      "imageUrl": "https://cdn.dummyjson.com/product-images/groceries/water/thumbnail.webp",
      "productCount": 1,
      "parentId": "4"
    },
    {
      "id": "20",
      "name": "Tea & Coffee",
      "iconName": "local_cafe",
      "imageUrl": "https://cdn.dummyjson.com/product-images/groceries/nescafe-coffee/thumbnail.webp",
      "productCount": 1,
      "parentId": "4"
    }
  ]
}
```

### Products (page 1)
`GET /api/v1/products?page=1&page_size=5` → **200**

```json
{
  "success": true,
  "message": "",
  "data": [
    {
      "id": "40",
      "name": "Ops Rice 2129",
      "brand": "Ops",
      "unit": "1 kg",
      "price": 60.0,
      "mrp": 75.0,
      "creditPrice": null,
      "discountPercent": 20,
      "discountAmount": 15.0,
      "categoryId": "29",
      "rating": 0.0,
      "reviews": 0,
      "imageUrl": null,
      "inStock": true,
      "stockCount": 197,
      "availableQuantity": 197
    },
    {
      "id": "39",
      "name": "Ops Rice 4964",
      "brand": "Ops",
      "unit": "1 kg",
      "price": 60.0,
      "mrp": 75.0,
      "creditPrice": null,
      "discountPercent": 20,
      "discountAmount": 15.0,
      "categoryId": "28",
      "rating": 0.0,
      "reviews": 0,
      "imageUrl": null,
      "inStock": true,
      "stockCount": 197,
      "availableQuantity": 197
    },
    {
      "id": "38",
      "name": "Ops Rice 4610",
      "brand": "Ops",
      "unit": "1 kg",
      "price": 60.0,
      "mrp": 75.0,
      "creditPrice": null,
      "discountPercent": 20,
      "discountAmount": 15.0,
      "categoryId": "27",
      "rating": 0.0,
      "reviews": 0,
      "imageUrl": null,
      "inStock": true,
      "stockCount": 100,
      "availableQuantity": 100
    },
    {
      "id": "37",
      "name": "PM Test Atta 5kg",
      "brand": "VS",
      "unit": "5 kg",
      "price": 250.0,
      "mrp": 300.0,
 
  … (truncated)
```

### Product detail
`GET /api/v1/products/40` → **200**

```json
{
  "success": true,
  "message": "",
  "data": {
    "id": "40",
    "name": "Ops Rice 2129",
    "brand": "Ops",
    "unit": "1 kg",
    "price": 60.0,
    "mrp": 75.0,
    "creditPrice": null,
    "discountPercent": 20,
    "discountAmount": 15.0,
    "categoryId": "29",
    "rating": 0.0,
    "reviews": 0,
    "imageUrl": null,
    "images": [],
    "inStock": true,
    "stockCount": 197,
    "availableQuantity": 197,
    "description": "",
    "specifications": {},
    "variants": []
  }
}
```

### Search
`GET /api/v1/products/search?q=milk` → **200**

```json
{
  "success": true,
  "message": "",
  "data": [
    {
      "id": "10",
      "name": "Milk",
      "brand": "Pure Dairy",
      "unit": "1 L",
      "price": 62.0,
      "mrp": 70.0,
      "creditPrice": null,
      "discountPercent": 11,
      "discountAmount": 8.0,
      "categoryId": "11",
      "rating": 4.0,
      "reviews": 1,
      "imageUrl": "https://cdn.dummyjson.com/product-images/groceries/milk/thumbnail.webp",
      "inStock": true,
      "stockCount": 50,
      "availableQuantity": 50
    }
  ],
  "meta": {
    "page": 1,
    "pageSize": 20,
    "total": 1,
    "totalPages": 1
  }
}
```

### Product not found (error)
`GET /api/v1/products/99999999` → **404**

```json
{
  "success": false,
  "code": "NOT_FOUND",
  "title": "Not Found",
  "message": "No Product matches the given query.",
  "action": null,
  "retryable": false,
  "severity": "warning",
  "nextStep": "Go back and try again.",
  "error": {
    "code": "NOT_FOUND",
    "message": "No Product matches the given query.",
    "fields": {}
  }
}
```


## Cart

### Cart
`GET /api/v1/cart` → **200**

```json
{
  "success": true,
  "message": "",
  "data": {
    "items": [
      {
        "id": "110",
        "productId": "1",
        "name": "Apple",
        "brand": "Fresh Farms",
        "unit": "1 kg",
        "imageUrl": "https://cdn.dummyjson.com/product-images/groceries/apple/thumbnail.webp",
        "price": 165.0,
        "mrp": 189.0,
        "quantity": 2,
        "lineTotal": 330.0
      },
      {
        "id": "111",
        "productId": "2",
        "name": "Kiwi",
        "brand": "Fresh Farms",
        "unit": "500 g",
        "imageUrl": "https://cdn.dummyjson.com/product-images/groceries/kiwi/thumbnail.webp",
        "price": 210.0,
        "mrp": 240.0,
        "quantity": 2,
        "lineTotal": 420.0
      },
      {
        "id": "112",
        "productId": "3",
        "name": "Lemon",
        "brand": "Fresh Farms",
        "unit": "250 g",
        "imageUrl": "https://cdn.dummyjson.com/product-images/groceries/lemon/thumbnail.webp",
        "price": 45.0,
        "mrp": 60.0,
        "quantity": 2,
        "lineTotal": 90.0
      }
    ],
    "bill": {
      "subtotal": 840.0,
      "savings": 138.0,
      "deliveryFee": 0.0,
      "gst": 151.2,
      "platformFee": 16.8,
      "smallCartFee": 0.0,
      "handlingFee": 0.0,
      "surgeFee": 0.0,
      "couponDiscount": 0.0,
      "total": 1008.0,
      "minOrder": 0.0,
      "itemsCount": 6
    }
  }
}
```

### Cart quote
`POST /api/v1/cart/quote` → **200**

```json
{
  "success": true,
  "message": "",
  "data": {
    "bill": {
      "subtotal": 120.0,
      "savings": 30.0,
      "deliveryFee": 45.0,
      "gst": 21.6,
      "platformFee": 2.4,
      "smallCartFee": 0.0,
      "handlingFee": 0.0,
      "surgeFee": 0.0,
      "couponDiscount": 0.0,
      "total": 189.0,
      "minOrder": 0.0,
      "itemsCount": 2
    }
  }
}
```

### Wishlist
`GET /api/v1/wishlist` → **200**

```json
{
  "success": true,
  "message": "",
  "data": [
    {
      "id": "6",
      "name": "Potatoes",
      "brand": "Fresh Farms",
      "unit": "2 kg",
      "price": 70.0,
      "mrp": 90.0,
      "creditPrice": null,
      "discountPercent": 22,
      "discountAmount": 20.0,
      "categoryId": "9",
      "rating": 4.2,
      "reviews": 150,
      "imageUrl": "https://cdn.dummyjson.com/product-images/groceries/potatoes/thumbnail.webp",
      "inStock": true,
      "stockCount": 50,
      "availableQuantity": 50
    },
    {
      "id": "5",
      "name": "Cucumber",
      "brand": "Fresh Farms",
      "unit": "500 g",
      "price": 40.0,
      "mrp": 55.0,
      "creditPrice": null,
      "discountPercent": 27,
      "discountAmount": 15.0,
      "categoryId": "9",
      "rating": 4.1,
      "reviews": 95,
      "imageUrl": "https://cdn.dummyjson.com/product-images/groceries/cucumber/thumbnail.webp",
      "inStock": true,
      "stockCount": 50,
      "availableQuantity": 49
    },
    {
      "id": "4",
      "name": "Strawberry",
      "brand": "Fresh Farms",
      "unit": "200 g",
      "price": 180.0,
      "mrp": 220.0,
      "creditPrice": null,
      "discountPercent": 18,
      "discountAmount": 40.0,
      "categoryId": "8",
      "rating": 4.6,
      "reviews": 310,
      "imageUrl": "https://cdn.dummyjson.com/product-images/groceries/strawberry/thumbnail.webp",
  
  … (truncated)
```


## Orders

### Order list
`GET /api/v1/orders` → **200**

```json
{
  "success": true,
  "message": "",
  "data": [
    {
      "id": "VSORD100102",
      "status": "confirmed",
      "placedAt": "2026-06-23T13:21:28.556330+05:30",
      "estimatedDelivery": null,
      "deliverySlot": "",
      "addressSnapshot": {
        "name": "Demo Customer",
        "phone": "+919000000007",
        "formatted": "42, 3rd Cross, Indiranagar, Bengaluru, Karnataka 560038",
        "pincode": "560038"
      },
      "paymentMethod": "upi",
      "paymentStatus": "paid",
      "subtotal": 750.0,
      "deliveryFee": 0.0,
      "gst": 135.0,
      "platformFee": 0.0,
      "discount": 0.0,
      "total": 885.0,
      "creditUsed": 0.0,
      "creditPlan": "",
      "creditDueDate": null,
      "couponCode": "",
      "items": [
        {
          "id": "91",
          "productId": "1",
          "name": "Apple",
          "brand": "Fresh Farms",
          "unit": "1 kg",
          "imageUrl": "https://cdn.dummyjson.com/product-images/groceries/apple/thumbnail.webp",
          "price": 165.0,
          "mrp": 189.0,
          "quantity": 2,
          "lineTotal": 330.0
        },
        {
          "id": "92",
          "productId": "2",
          "name": "Kiwi",
          "brand": "Fresh Farms",
          "unit": "500 g",
          "imageUrl": "https://cdn.dummyjson.com/product-images/groceries/kiwi/thumbnail.webp",
          "price": 210.0,
          "mrp
  … (truncated)
```

### Active orders
`GET /api/v1/orders?status=active` → **200**

```json
{
  "success": true,
  "message": "",
  "data": [
    {
      "id": "VSORD100102",
      "status": "confirmed",
      "placedAt": "2026-06-23T13:21:28.556330+05:30",
      "estimatedDelivery": null,
      "deliverySlot": "",
      "addressSnapshot": {
        "name": "Demo Customer",
        "phone": "+919000000007",
        "formatted": "42, 3rd Cross, Indiranagar, Bengaluru, Karnataka 560038",
        "pincode": "560038"
      },
      "paymentMethod": "upi",
      "paymentStatus": "paid",
      "subtotal": 750.0,
      "deliveryFee": 0.0,
      "gst": 135.0,
      "platformFee": 0.0,
      "discount": 0.0,
      "total": 885.0,
      "creditUsed": 0.0,
      "creditPlan": "",
      "creditDueDate": null,
      "couponCode": "",
      "items": [
        {
          "id": "91",
          "productId": "1",
          "name": "Apple",
          "brand": "Fresh Farms",
          "unit": "1 kg",
          "imageUrl": "https://cdn.dummyjson.com/product-images/groceries/apple/thumbnail.webp",
          "price": 165.0,
          "mrp": 189.0,
          "quantity": 2,
          "lineTotal": 330.0
        },
        {
          "id": "92",
          "productId": "2",
          "name": "Kiwi",
          "brand": "Fresh Farms",
          "unit": "500 g",
          "imageUrl": "https://cdn.dummyjson.com/product-images/groceries/kiwi/thumbnail.webp",
          "price": 210.0,
          "mrp
  … (truncated)
```

### Order detail
`GET /api/v1/orders/VSORD100099` → **200**

```json
{
  "success": true,
  "message": "",
  "data": {
    "id": "VSORD100099",
    "status": "delivered",
    "placedAt": "2026-06-17T13:21:28.556330+05:30",
    "estimatedDelivery": null,
    "deliverySlot": "",
    "addressSnapshot": {
      "name": "Demo Customer",
      "phone": "+919000000007",
      "formatted": "42, 3rd Cross, Indiranagar, Bengaluru, Karnataka 560038",
      "pincode": "560038"
    },
    "paymentMethod": "upi",
    "paymentStatus": "paid",
    "subtotal": 840.0,
    "deliveryFee": 0.0,
    "gst": 151.2,
    "platformFee": 0.0,
    "discount": 0.0,
    "total": 991.2,
    "creditUsed": 0.0,
    "creditPlan": "",
    "creditDueDate": null,
    "couponCode": "",
    "items": [
      {
        "id": "82",
        "productId": "1",
        "name": "Apple",
        "brand": "Fresh Farms",
        "unit": "1 kg",
        "imageUrl": "https://cdn.dummyjson.com/product-images/groceries/apple/thumbnail.webp",
        "price": 165.0,
        "mrp": 189.0,
        "quantity": 2,
        "lineTotal": 330.0
      },
      {
        "id": "83",
        "productId": "2",
        "name": "Kiwi",
        "brand": "Fresh Farms",
        "unit": "500 g",
        "imageUrl": "https://cdn.dummyjson.com/product-images/groceries/kiwi/thumbnail.webp",
        "price": 210.0,
        "mrp": 240.0,
        "quantity": 2,
        "lineTotal": 420.0
      },
      {
        "id": "84",
  … (truncated)
```

### Live tracking
`GET /api/v1/orders/VSORD100101/tracking` → **200**

```json
{
  "success": true,
  "message": "",
  "data": {
    "orderId": "VSORD100101",
    "status": "out_for_delivery",
    "agentName": "Ravi Kumar",
    "latitude": 12.974,
    "longitude": 77.621,
    "eta": "12 mins"
  }
}
```


## Credit

### Dashboard
`GET /api/v1/credit/dashboard` → **200**

```json
{
  "success": true,
  "message": "",
  "data": {
    "creditLimit": 25000.0,
    "outstanding": 2399.0,
    "available": 22601.0,
    "vsScore": 742,
    "status": "active",
    "billingCycle": "monthly",
    "lenderName": "VS Finance Partners NBFC",
    "loanAccountNumber": "VSL00010042",
    "interestRate": 18.0,
    "sanctionedLimit": 25000.0,
    "nextDueDate": "2026-06-30",
    "nextDueAmount": 2399.0,
    "purchasesThisMonth": 6050.0,
    "paymentsThisMonth": 3000.0
  }
}
```

### Ledger
`GET /api/v1/credit/ledger` → **200**

```json
{
  "success": true,
  "message": "",
  "data": [
    {
      "id": "92",
      "type": "refund",
      "amount": -600.0,
      "balanceAfter": 2399.0,
      "note": "Return refund",
      "createdAt": "2026-06-23T13:21:29.228047+05:30"
    },
    {
      "id": "91",
      "type": "adjustment",
      "amount": -100.0,
      "balanceAfter": 2999.0,
      "note": "Goodwill credit",
      "createdAt": "2026-06-23T13:21:29.216402+05:30"
    },
    {
      "id": "90",
      "type": "fee",
      "amount": 49.0,
      "balanceAfter": 3099.0,
      "note": "Late fee",
      "createdAt": "2026-06-23T13:21:29.205039+05:30"
    },
    {
      "id": "89",
      "type": "repayment",
      "amount": -3000.0,
      "balanceAfter": 3050.0,
      "note": "UPI repayment",
      "createdAt": "2026-06-23T13:21:29.193504+05:30"
    },
    {
      "id": "88",
      "type": "purchase",
      "amount": 1850.0,
      "balanceAfter": 6050.0,
      "note": "Order VSORD staples",
      "createdAt": "2026-06-23T13:21:29.182111+05:30"
    },
    {
      "id": "87",
      "type": "purchase",
      "amount": 4200.0,
      "balanceAfter": 4200.0,
      "note": "Order VSORD groceries",
      "createdAt": "2026-06-23T13:21:29.170402+05:30"
    }
  ],
  "meta": {
    "page": 1,
    "pageSize": 20,
    "total": 6,
    "totalPages": 1
  }
}
```

### Statements
`GET /api/v1/credit/statements` → **200**

```json
{
  "success": true,
  "message": "",
  "data": [
    {
      "id": "2",
      "period": "monthly",
      "periodStart": "2026-05-02",
      "periodEnd": "2026-05-31",
      "openingBalance": 0.0,
      "purchases": 6050.0,
      "payments": 3000.0,
      "fees": 49.0,
      "closingBalance": 2399.0,
      "dueDate": "2026-06-30",
      "status": "open"
    }
  ]
}
```

### Outstanding
`GET /api/v1/credit/outstanding` → **200**

```json
{
  "success": true,
  "message": "",
  "data": {
    "total": 2399.0,
    "statements": [
      {
        "id": "2",
        "period": "monthly",
        "periodStart": "2026-05-02",
        "periodEnd": "2026-05-31",
        "openingBalance": 0.0,
        "purchases": 6050.0,
        "payments": 3000.0,
        "fees": 49.0,
        "closingBalance": 2399.0,
        "dueDate": "2026-06-30",
        "status": "open"
      }
    ]
  }
}
```


## Billing

### Invoices
`GET /api/v1/billing/invoices` → **200**

```json
{
  "success": true,
  "message": "",
  "data": [],
  "meta": {
    "page": 1,
    "pageSize": 20,
    "total": 0,
    "totalPages": 1
  }
}
```

### Payment history
`GET /api/v1/payments/history` → **200**

```json
{
  "success": true,
  "message": "",
  "data": [],
  "meta": {
    "page": 1,
    "pageSize": 20,
    "total": 0,
    "totalPages": 1
  }
}
```


## Offers

### Offers
`GET /api/v1/offers` → **200**

```json
{
  "success": true,
  "message": "",
  "data": [
    {
      "id": "1",
      "type": "deal",
      "placement": "top",
      "title": "Deal of day",
      "subtitle": "",
      "code": "",
      "imageUrl": null,
      "badge": "",
      "discountPercent": 34,
      "dealPrice": 99.0,
      "originalPrice": 150.0,
      "productId": null,
      "validTo": null
    },
    {
      "id": "2",
      "type": "banner",
      "placement": "top",
      "title": "Flat 20% Off",
      "subtitle": "On fresh fruits & vegetables",
      "code": "",
      "imageUrl": "https://cdn.dummyjson.com/product-images/groceries/apple/thumbnail.webp",
      "badge": "Weekend Special",
      "discountPercent": 20,
      "dealPrice": null,
      "originalPrice": null,
      "productId": null,
      "validTo": null
    },
    {
      "id": "8",
      "type": "coupon",
      "placement": "top",
      "title": "\u20b9100 off above \u20b9999",
      "subtitle": "On all categories",
      "code": "VS100",
      "imageUrl": null,
      "badge": "",
      "discountPercent": null,
      "dealPrice": null,
      "originalPrice": null,
      "productId": null,
      "validTo": null
    },
    {
      "id": "3",
      "type": "banner",
      "placement": "top",
      "title": "Shop Now, Pay Later",
      "subtitle": "Up to \u20b910,000 instant VS Credit",
      "code": "",
      "imageUrl": "https://cdn.dummyjson
  … (truncated)
```

### Coupon wallet
`GET /api/v1/coupons/wallet` → **200**

```json
{
  "success": true,
  "message": "",
  "data": [
    {
      "id": "5",
      "code": "VSNEW100",
      "discountType": "flat",
      "value": 100.0,
      "minOrder": 499.0,
      "maxDiscount": null,
      "validTo": "2026-07-21"
    },
    {
      "id": "4",
      "code": "BIG20",
      "discountType": "percent",
      "value": 20.0,
      "minOrder": 1499.0,
      "maxDiscount": 300.0,
      "validTo": "2026-07-21"
    },
    {
      "id": "3",
      "code": "WEEKEND50",
      "discountType": "flat",
      "value": 50.0,
      "minOrder": 299.0,
      "maxDiscount": null,
      "validTo": "2026-07-05"
    },
    {
      "id": "2",
      "code": "FRESH15",
      "discountType": "percent",
      "value": 15.0,
      "minOrder": null,
      "maxDiscount": 150.0,
      "validTo": null
    },
    {
      "id": "1",
      "code": "VS100",
      "discountType": "flat",
      "value": 100.0,
      "minOrder": 999.0,
      "maxDiscount": null,
      "validTo": null
    }
  ]
}
```

### Coupon validate (valid)
`POST /api/v1/coupons/validate` → **200**

```json
{
  "success": true,
  "message": "",
  "data": {
    "valid": true,
    "discount": 100.0,
    "message": "Applied"
  }
}
```

### Coupon validate (invalid, error)
`POST /api/v1/coupons/validate` → **200**

```json
{
  "success": true,
  "message": "",
  "data": {
    "valid": false,
    "discount": 0.0,
    "message": "Invalid coupon code"
  }
}
```


## KYC

### Status
`GET /api/v1/kyc/status` → **200**

```json
{
  "success": true,
  "message": "",
  "data": {
    "id": "36",
    "status": "verified",
    "submittedAt": "2026-06-03T13:21:29.249970+05:30",
    "reviewedAt": "2026-06-04T13:21:29.249980+05:30",
    "rejectionReason": "",
    "steps": [
      {
        "step": "aadhaar",
        "status": "approved",
        "note": ""
      },
      {
        "step": "pan",
        "status": "approved",
        "note": ""
      },
      {
        "step": "selfie",
        "status": "approved",
        "note": ""
      },
      {
        "step": "residence",
        "status": "approved",
        "note": ""
      }
    ],
    "documents": [
      {
        "id": "61",
        "type": "residence",
        "numberMasked": "",
        "status": "approved",
        "url": null
      },
      {
        "id": "60",
        "type": "selfie",
        "numberMasked": "",
        "status": "approved",
        "url": null
      },
      {
        "id": "59",
        "type": "pan",
        "numberMasked": "ABCDXXXXXF",
        "status": "approved",
        "url": null
      },
      {
        "id": "58",
        "type": "aadhaar",
        "numberMasked": "XXXX XXXX 1234",
        "status": "approved",
        "url": null
      }
    ]
  }
}
```


## Addresses

### List
`GET /api/v1/addresses` → **200**

```json
{
  "success": true,
  "message": "",
  "data": [
    {
      "id": "54",
      "label": "Home",
      "name": "Demo Customer",
      "phone": "+919000000007",
      "line1": "42, 3rd Cross, Indiranagar",
      "village": "Indiranagar",
      "area": "Indiranagar",
      "landmark": "",
      "city": "Bengaluru",
      "district": "Bengaluru Urban",
      "state": "Karnataka",
      "pincode": "560038",
      "latitude": 12.9719,
      "longitude": 77.6412,
      "isDefault": true,
      "formatted": "42, 3rd Cross, Indiranagar, Indiranagar, Indiranagar, Bengaluru Urban, Karnataka, 560038"
    },
    {
      "id": "55",
      "label": "Work",
      "name": "Demo Customer",
      "phone": "+919000000007",
      "line1": "VS Mart HQ, MG Road",
      "village": "Bengaluru",
      "area": "MG Road",
      "landmark": "",
      "city": "Bengaluru",
      "district": "Bengaluru Urban",
      "state": "Karnataka",
      "pincode": "560001",
      "latitude": 12.975,
      "longitude": 77.6,
      "isDefault": false,
      "formatted": "VS Mart HQ, MG Road, Bengaluru, MG Road, Bengaluru Urban, Karnataka, 560001"
    }
  ]
}
```


## Notifications

### Inbox
`GET /api/v1/notifications` → **200**

```json
{
  "success": true,
  "message": "",
  "data": [
    {
      "id": "145",
      "type": "order",
      "title": "Out for delivery",
      "body": "Ravi is on the way with your order.",
      "data": {},
      "readAt": "2026-06-23T13:21:29.423320+05:30",
      "createdAt": "2026-06-23T13:21:29.407055+05:30",
      "isRead": true
    },
    {
      "id": "144",
      "type": "offer",
      "title": "Weekend offer",
      "body": "Flat 20% off on fresh fruits & vegetables.",
      "data": {},
      "readAt": "2026-06-23T13:21:29.396152+05:30",
      "createdAt": "2026-06-23T13:21:29.385730+05:30",
      "isRead": true
    },
    {
      "id": "143",
      "type": "credit",
      "title": "Credit approved",
      "body": "Your VS Credit limit is now \u20b925,000.",
      "data": {},
      "readAt": null,
      "createdAt": "2026-06-23T13:21:29.376188+05:30",
      "isRead": false
    },
    {
      "id": "142",
      "type": "payment",
      "title": "Payment due soon",
      "body": "\u20b93,099 is due on your VS Credit in 7 days.",
      "data": {},
      "readAt": null,
      "createdAt": "2026-06-23T13:21:29.365992+05:30",
      "isRead": false
    },
    {
      "id": "141",
      "type": "order",
      "title": "Order delivered",
      "body": "Your order VSORD100000 was delivered. Enjoy!",
      "data": {},
      "readAt": null,
      "createdAt": "2026-06-23T13:21:29.3557
  … (truncated)
```

### Preferences
`GET /api/v1/notifications/preferences` → **200**

```json
{
  "success": true,
  "message": "",
  "data": {
    "id": "33",
    "push": true,
    "sms": false,
    "whatsapp": true,
    "email": false,
    "reminderTime": null,
    "reminderEnabled": true,
    "reminderOffsetDays": 3,
    "categories": {}
  }
}
```


## Support

### FAQs
`GET /api/v1/support/faqs` → **200**

```json
{
  "success": true,
  "message": "",
  "data": [
    {
      "id": "1",
      "category": "Orders",
      "question": "How to track?",
      "answer": "Open the order."
    },
    {
      "id": "2",
      "category": "Credit",
      "question": "How does VS Credit work?",
      "answer": "Buy groceries now and pay later. After KYC approval you get a credit limit to use at checkout; your spend is billed monthly and is interest-free if cleared by the due date."
    },
    {
      "id": "3",
      "category": "Payments",
      "question": "How do I pay my outstanding amount?",
      "answer": "Open the Credit tab and tap Pay Now. Settle via UPI, card, or net-banking \u2014 payments reflect instantly and restore your limit."
    },
    {
      "id": "4",
      "category": "Credit",
      "question": "How can I increase my credit limit?",
      "answer": "Your limit is reviewed automatically based on repayment history and activity. Paying on time and keeping KYC current improves eligibility."
    },
    {
      "id": "5",
      "category": "Payments",
      "question": "What happens if I miss a payment?",
      "answer": "A nominal late fee may apply and credit may pause until cleared. We send reminders before the due date."
    },
    {
      "id": "6",
      "category": "Orders",
      "question": "How can I contact support?",
      "answer": "Use the Support tab \u2014 Contact S
  … (truncated)
```

### Tickets
`GET /api/v1/support/tickets` → **200**

```json
{
  "success": true,
  "message": "",
  "data": [
    {
      "id": "TKT1030",
      "category": "Payment",
      "priority": "medium",
      "subject": "Payment Problem",
      "status": "resolved",
      "createdAt": "2026-06-23T13:21:29.520236+05:30"
    },
    {
      "id": "TKT1029",
      "category": "Order",
      "priority": "high",
      "subject": "Order Issue",
      "status": "open",
      "createdAt": "2026-06-23T13:21:29.490210+05:30"
    }
  ]
}
```

### Ticket detail
`GET /api/v1/support/tickets/TKT1030` → **200**

```json
{
  "success": true,
  "message": "",
  "data": {
    "id": "TKT1030",
    "category": "Payment",
    "priority": "medium",
    "subject": "Payment Problem",
    "status": "resolved",
    "orderCode": "",
    "createdAt": "2026-06-23T13:21:29.520236+05:30",
    "messages": [
      {
        "senderName": "Demo Shopper",
        "body": "Repayment not reflecting.",
        "attachments": null,
        "createdAt": "2026-06-23T13:21:29.540168+05:30"
      },
      {
        "senderName": "Demo Shopper",
        "body": "Resolved now, thanks!",
        "attachments": null,
        "createdAt": "2026-06-23T13:21:29.550533+05:30"
      }
    ]
  }
}
```


## Loyalty

### Status
`GET /api/v1/loyalty` → **200**

```json
{
  "success": true,
  "message": "",
  "data": {
    "balance": 160,
    "lifetimeEarned": 210,
    "tier": "Bronze"
  }
}
```

### Ledger
`GET /api/v1/loyalty/ledger` → **200**

```json
{
  "success": true,
  "message": "",
  "data": [
    {
      "id": "18",
      "type": "redeem",
      "points": -50,
      "balanceAfter": 160,
      "note": "Redeemed to wallet",
      "createdAt": "2026-06-23T13:21:29.456237+05:30"
    },
    {
      "id": "17",
      "type": "earn",
      "points": 90,
      "balanceAfter": 210,
      "note": "Order VSORD100001",
      "createdAt": "2026-06-23T13:21:29.445652+05:30"
    },
    {
      "id": "16",
      "type": "earn",
      "points": 120,
      "balanceAfter": 120,
      "note": "Order VSORD100000",
      "createdAt": "2026-06-23T13:21:29.434869+05:30"
    }
  ]
}
```

### Redeem too many (actionable error)
`POST /api/v1/loyalty/redeem` → **400**

```json
{
  "success": false,
  "code": "INSUFFICIENT_POINTS",
  "title": "Not Enough Points",
  "message": "You don't have enough points to redeem that amount.",
  "action": null,
  "retryable": false,
  "severity": "warning",
  "nextStep": "Earn more points or redeem a smaller amount.",
  "error": {
    "code": "INSUFFICIENT_POINTS",
    "message": "You don't have enough points to redeem that amount.",
    "fields": {}
  }
}
```


## Referrals

### Referral
`GET /api/v1/referrals` → **200**

```json
{
  "success": true,
  "message": "",
  "data": {
    "id": "35",
    "code": "VS00333F1",
    "reward": 100.0,
    "status": "completed",
    "referredCount": 1
  }
}
```

### Invalid code (actionable error)
`POST /api/v1/referrals/apply` → **400**

```json
{
  "success": false,
  "code": "REFERRAL_INVALID",
  "title": "Invalid Code",
  "message": "This referral code isn't valid.",
  "action": null,
  "retryable": false,
  "severity": "warning",
  "nextStep": "Double-check the code and try again.",
  "error": {
    "code": "REFERRAL_INVALID",
    "message": "This referral code isn't valid.",
    "fields": {}
  }
}
```


## Subscriptions

### List
`GET /api/v1/subscriptions` → **200**

```json
{
  "success": true,
  "message": "",
  "data": [
    {
      "id": "11",
      "quantity": 2,
      "frequency": "monthly",
      "status": "paused",
      "nextDelivery": "2026-07-13",
      "createdAt": "2026-06-23T13:21:29.572838+05:30",
      "productId": "2",
      "productName": "Kiwi",
      "price": 210.0,
      "imageUrl": "https://cdn.dummyjson.com/product-images/groceries/kiwi/thumbnail.webp"
    },
    {
      "id": "10",
      "quantity": 1,
      "frequency": "weekly",
      "status": "active",
      "nextDelivery": "2026-06-26",
      "createdAt": "2026-06-23T13:21:29.562673+05:30",
      "productId": "1",
      "productName": "Apple",
      "price": 165.0,
      "imageUrl": "https://cdn.dummyjson.com/product-images/groceries/apple/thumbnail.webp"
    }
  ]
}
```


## Returns

### List
`GET /api/v1/returns` → **200**

```json
{
  "success": true,
  "message": "",
  "data": [
    {
      "id": "RET1008",
      "orderCode": "VSORD100099",
      "reason": "Damaged item",
      "description": "One pack arrived damaged.",
      "status": "approved",
      "refundAmount": 180.0,
      "createdAt": "2026-06-23T13:21:29.584242+05:30",
      "resolvedAt": null,
      "items": [
        {
          "productName": "Apple",
          "quantity": 1,
          "amount": 180.0
        }
      ]
    }
  ]
}
```


## Reviews

### Product reviews
`GET /api/v1/products/40/reviews` → **200**

```json
{
  "success": true,
  "message": "",
  "data": {
    "reviews": [],
    "summary": {
      "average": 0,
      "count": 0,
      "distribution": {
        "1": 0,
        "2": 0,
        "3": 0,
        "4": 0,
        "5": 0
      }
    }
  }
}
```

### My reviews
`GET /api/v1/reviews/mine` → **200**

```json
{
  "success": true,
  "message": "",
  "data": [
    {
      "id": "11",
      "rating": 4,
      "title": "Good value",
      "body": "Tasty, would buy again.",
      "createdAt": "2026-06-23T13:21:29.630727+05:30",
      "authorName": "Demo Shopper"
    },
    {
      "id": "10",
      "rating": 5,
      "title": "Excellent",
      "body": "Fresh and well packed.",
      "createdAt": "2026-06-23T13:21:29.619400+05:30",
      "authorName": "Demo Shopper"
    }
  ]
}
```


## Serviceability

### Serviceable
`GET /api/v1/serviceability/check?lat=12.97&lng=77.6&pincode=560038` → **200**

```json
{
  "success": true,
  "message": "",
  "data": {
    "serviceable": true,
    "zoneId": "7",
    "zoneName": "Bengaluru Central",
    "storeId": "1",
    "storeName": "VS Mart Bengaluru Central",
    "deliveryFee": 15.0,
    "minimumOrder": 99.0,
    "creditAvailable": true,
    "estimatedDeliveryTime": 20,
    "freeDeliveryThreshold": 199.0
  }
}
```

### Not serviceable
`GET /api/v1/serviceability/check?lat=0&lng=0&pincode=000000` → **200**

```json
{
  "success": true,
  "message": "",
  "data": {
    "serviceable": false,
    "zoneId": null,
    "zoneName": null,
    "storeId": null,
    "storeName": null,
    "deliveryFee": null,
    "minimumOrder": null,
    "creditAvailable": false,
    "estimatedDeliveryTime": null,
    "freeDeliveryThreshold": null
  }
}
```


## Content

### Terms page
`GET /api/v1/content/pages/terms` → **200**

```json
{
  "success": true,
  "message": "",
  "data": {
    "id": "4",
    "slug": "terms",
    "title": "Terms of Service",
    "body": "Welcome to VS Mart. By accessing or using our app and services, you agree to be bound by these Terms of Service. Please read them carefully before placing an order.\n\nUse of the Service: You agree to provide accurate account information and to use VS Mart only for lawful purposes. You are responsible for maintaining the confidentiality of your account credentials and for all activity under your account.\n\nOrders and Pricing: All orders are subject to acceptance and availability. Prices, offers, and product information are subject to change without notice. We make every effort to ensure accuracy, but errors may occasionally occur, and we reserve the right to correct them.\n\nPayments and Credit: Where credit facilities are offered, repayment terms and any applicable charges will be disclosed at the time of use. Failure to repay outstanding amounts may affect your eligibility for future credit.\n\nLimitation of Liability: VS Mart is not liable for any indirect or consequential losses arising from the use of the service, to the maximum extent permitted by law. We may update these terms from time to time, and continued use of the service constitutes acceptance of the revised terms.",
    "type": "terms",
    "updatedAt": "2026-06-21T11:17:38.157713+0
  … (truncated)
```
