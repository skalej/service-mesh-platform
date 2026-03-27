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
    fun `products query returns all products`() {
        val names: List<String> =
            dgs.executeAndExtractJsonPath(
                "{ products { name } }",
                "data.products[*].name",
            )
        assertThat(names).hasSize(5)
        assertThat(names).contains("Mechanical Keyboard", "USB-C Hub")
    }

    @Test
    fun `products query returns correct prices`() {
        val prices: List<Double> =
            dgs.executeAndExtractJsonPath(
                "{ products { price } }",
                "data.products[*].price",
            )
        assertThat(prices).contains(129.99, 49.99, 399.99)
    }
}
