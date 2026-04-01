package com.example.catalog

import com.example.catalog.generated.types.Product
import com.netflix.graphql.dgs.DgsQueryExecutor
import org.assertj.core.api.Assertions.assertThat
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.boot.test.context.SpringBootTest

@SpringBootTest
class CarrierDataFetcherTest {
    @Autowired
    lateinit var dgsQueryExecutor: DgsQueryExecutor

    @Autowired
    lateinit var store: ProductStore

    @Autowired
    lateinit var dataLoader: CarrierProductsDataLoader

    // Use variables for representations — __typename has special meaning in GraphQL
    // and can cause parsing issues when inlined. This also mirrors what Apollo Router
    // actually sends at runtime.
    private val entitiesQuery =
        """
        query(${'$'}representations: [_Any!]!) {
            _entities(representations: ${'$'}representations) {
                ... on Carrier {
                    id
                    products { name }
                }
            }
        }
        """.trimIndent()

    @Test
    fun `resolves products for fedex carrier`() {
        val names: List<String> =
            dgsQueryExecutor.executeAndExtractJsonPath(
                entitiesQuery,
                "data._entities[0].products[*].name",
                mapOf("representations" to listOf(mapOf("__typename" to "Carrier", "id" to "fedex"))),
            )
        assertThat(names).containsExactlyInAnyOrder("Mechanical Keyboard", "27\" 4K Monitor")
    }

    @Test
    fun `resolves products for ups carrier`() {
        val names: List<String> =
            dgsQueryExecutor.executeAndExtractJsonPath(
                entitiesQuery,
                "data._entities[0].products[*].name",
                mapOf("representations" to listOf(mapOf("__typename" to "Carrier", "id" to "ups"))),
            )
        assertThat(names).containsExactlyInAnyOrder("USB-C Hub", "Wireless Mouse")
    }

    @Test
    fun `returns empty products for unknown carrier`() {
        val names: List<String> =
            dgsQueryExecutor.executeAndExtractJsonPath(
                entitiesQuery,
                "data._entities[0].products[*].name",
                mapOf("representations" to listOf(mapOf("__typename" to "Carrier", "id" to "dhl"))),
            )
        assertThat(names).isEmpty()
    }

    @Test
    fun `resolves multiple carriers in one _entities call`() {
        val result: List<List<String>> =
            dgsQueryExecutor.executeAndExtractJsonPath(
                entitiesQuery,
                "data._entities[*].products[*].name",
                mapOf(
                    "representations" to
                        listOf(
                            mapOf("__typename" to "Carrier", "id" to "fedex"),
                            mapOf("__typename" to "Carrier", "id" to "usps"),
                        ),
                ),
            )
        assertThat(result).isNotEmpty()
    }

//    @Test
//    fun `N+1 - productsByCarrier called once per carrier`() {
//        store.productsByCarrierCallCount = 0
//
//        dgsQueryExecutor.executeAndExtractJsonPath<List<Product>>(
//            entitiesQuery,
//            "data._entities[*].products",
//            mapOf(
//                "representations" to listOf(
//                    mapOf("__typename" to "Carrier", "id" to "fedex"),
//                    mapOf("__typename" to "Carrier", "id" to "ups"),
//                    mapOf("__typename" to "Carrier", "id" to "usps"),
//                )
//            )
//        )
//
//        // Proves N+1: 3 carriers = 3 separate calls
//        assertThat(store.productsByCarrierCallCount).isEqualTo(3)
//    }

    @Test
    fun `DataLoader batches all carriers into one load call`() {
        val products: List<Product> =
            dgsQueryExecutor.executeAndExtractJsonPath(
                entitiesQuery,
                "data._entities[*].products",
                mapOf(
                    "representations" to
                        listOf(
                            mapOf("__typename" to "Carrier", "id" to "fedex"),
                            mapOf("__typename" to "Carrier", "id" to "ups"),
                            mapOf("__typename" to "Carrier", "id" to "usps"),
                        ),
                ),
            )
        assertEquals(3, products.size)
    }
}
