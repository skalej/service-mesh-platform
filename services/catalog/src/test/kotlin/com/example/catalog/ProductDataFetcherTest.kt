package com.example.catalog

import com.netflix.graphql.dgs.DgsQueryExecutor
import org.assertj.core.api.Assertions.assertThat
import org.junit.jupiter.api.Test
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.boot.test.context.SpringBootTest

@SpringBootTest
class ProductDataFetcherTest {
    @Autowired
    lateinit var dgs: DgsQueryExecutor

    @Test
    fun `products returns first page`() {
        val names: List<String> =
            dgs.executeAndExtractJsonPath(
                "{ productsConnection(first: 2) { edges { node { name } } } }",
                "data.productsConnection.edges[*].node.name",
            )
        assertThat(names).hasSize(2)
    }

    @Test
    fun `products returns next page using cursor`() {
        val endCursor: String =
            dgs.executeAndExtractJsonPath(
                "{ productsConnection(first: 2) { pageInfo { endCursor hasNextPage } } }",
                "data.productsConnection.pageInfo.endCursor",
            )

        val names: List<String> =
            dgs.executeAndExtractJsonPath(
                "{ productsConnection(first: 2, after: \"$endCursor\") { edges { node { name } } } }",
                "data.productsConnection.edges[*].node.name",
            )
        assertThat(names).hasSize(2)
    }

    @Test
    fun `pageInfo hasNextPage is false on last page`() {
        val hasNextPage: Boolean =
            dgs.executeAndExtractJsonPath(
                "{ productsConnection(first: 100) { pageInfo { hasNextPage } } }",
                "data.productsConnection.pageInfo.hasNextPage",
            )
        assertThat(hasNextPage).isFalse()
    }

    @Test
    fun `products filter by nameContains`() {
        val names: List<String> =
            dgs.executeAndExtractJsonPath(
                "{ productsConnection(filter: { nameContains: \"Mouse\" }, first: 2) { edges { node { name } } } }",
                "data.productsConnection.edges[*].node.name",
            )
        assertThat(names).containsExactly("Wireless Mouse")
    }

    @Test
    fun `products filter by price range`() {
        val names: List<String> =
            dgs.executeAndExtractJsonPath(
                "{ productsConnection(filter: { minPrice: 50, maxPrice: 200 }, first: 5) { edges { node { name } } } }",
                "data.productsConnection.edges[*].node.name",
            )
        assertThat(names).contains("Laptop Stand", "Mechanical Keyboard")
        assertThat(names).doesNotContain("27\" 4K Monitor", "Wireless Mouse")
    }

    @Test
    fun `products sorted by price ascending`() {
        val prices: List<Double> =
            dgs.executeAndExtractJsonPath(
                "{ productsConnection(sort: { field: PRICE, direction: ASC }, first: 10) { edges { node { price } } } }",
                "data.productsConnection.edges[*].node.price",
            )
        assertThat(prices).isSortedAccordingTo(compareBy { it })
    }

    @Test
    fun `products sorted by price descending`() {
        val prices: List<Double> =
            dgs.executeAndExtractJsonPath(
                "{ productsConnection(sort: { field: PRICE, direction: DESC }, first: 10) { edges { node { price } } } }",
                "data.productsConnection.edges[*].node.price",
            )
        assertThat(prices).isSortedAccordingTo(compareByDescending { it })
    }

    @Test
    fun `product query returns single product by id`() {
        val name: String =
            dgs.executeAndExtractJsonPath(
                "{ product(id: \"1\") { name } }",
                "data.product.name",
            )
        assertThat(name).isEqualTo("Mechanical Keyboard")
    }

    @Test
    fun `product query returns null for unknown id`() {
        val result = dgs.execute("{ product(id: \"999\") { name } }")
        assertThat(result.errors).isEmpty()
        val product = result.getData<Map<String, Any>>()["product"]
        assertThat(product).isNull()
    }
}
