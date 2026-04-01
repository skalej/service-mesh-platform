package com.example.catalog

import com.example.catalog.generated.DgsConstants
import com.example.catalog.generated.types.PageInfo
import com.example.catalog.generated.types.Product
import com.example.catalog.generated.types.ProductConnection
import com.example.catalog.generated.types.ProductEdge
import com.example.catalog.generated.types.ProductFilter
import com.example.catalog.generated.types.ProductSort
import com.example.catalog.generated.types.SortDirection
import com.example.catalog.generated.types.SortField
import com.netflix.graphql.dgs.DgsComponent
import com.netflix.graphql.dgs.DgsEntityFetcher
import com.netflix.graphql.dgs.DgsQuery
import com.netflix.graphql.dgs.InputArgument

@DgsComponent
class ProductDataFetcher(
    private val store: ProductStore,
) {
    @DgsQuery(field = DgsConstants.QUERY.ProductsConnection)
    fun products(
        @InputArgument filter: ProductFilter?,
        @InputArgument sort: ProductSort?,
        @InputArgument first: Int?,
        @InputArgument after: String?,
    ): ProductConnection {
        var result: List<Product> = store.findAll()

        filter?.let {
            it.nameContains?.let { q -> result = result.filter { p -> p.name!!.contains(q, ignoreCase = true) } }
            it.minPrice?.let { min -> result = result.filter { p -> p.price!! >= min } }
            it.maxPrice?.let { max -> result = result.filter { p -> p.price!! <= max } }
        }

        sort?.let {
            val comparator =
                when (it.field) {
                    SortField.NAME -> compareBy<Product> { p -> p.name }
                    SortField.PRICE -> compareBy<Product> { p -> p.price }
                }
            result =
                if (it.direction == SortDirection.DESC) {
                    result.sortedWith(comparator.reversed())
                } else {
                    result.sortedWith(comparator)
                }
        }

        // Apply cursor — skip everything up to and including the `after` position
        val startIndex = after?.let { decodeCursor(it) + 1 } ?: 0
        val sliced = result.drop(startIndex)

        // Apply page size
        val pageSize = first ?: sliced.size
        val page = sliced.take(pageSize)

        val edges =
            page.mapIndexed { i, product ->
                ProductEdge(
                    node = product,
                    cursor = encodeCursor(startIndex + i),
                )
            }

        val pageInfo =
            PageInfo(
                hasNextPage = startIndex + page.size < result.size,
                hasPreviousPage = startIndex > 0,
                startCursor = edges.firstOrNull()?.cursor,
                endCursor = edges.lastOrNull()?.cursor,
            )

        return ProductConnection(edges = edges, pageInfo = pageInfo)
    }

    @DgsQuery
    fun product(
        @InputArgument id: String,
    ): Product? = store.findById(id)

    @DgsEntityFetcher(name = "Product")
    fun resolveProduct(values: Map<String, Any>): Product? = store.findById(values["id"].toString())
}
