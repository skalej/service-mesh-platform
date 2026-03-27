package com.example.catalog

import com.example.catalog.generated.types.Product
import com.netflix.graphql.dgs.DgsComponent
import com.netflix.graphql.dgs.DgsQuery

@DgsComponent
class ProductDataFetcher {
    @DgsQuery
    fun products(): List<Product> =
        listOf(
            Product(id = "1", name = "Mechanical Keyboard", price = 129.99),
            Product(id = "2", name = "USB-C Hub", price = 49.99),
            Product(id = "3", name = "27\" 4K Monitor", price = 399.99),
            Product(id = "4", name = "Wireless Mouse", price = 34.99),
            Product(id = "5", name = "Laptop Stand", price = 59.99),
        )
}
