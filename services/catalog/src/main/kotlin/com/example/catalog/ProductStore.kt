package com.example.catalog

import com.example.catalog.generated.types.Product
import org.springframework.stereotype.Component
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicInteger

@Component
class ProductStore {
    private val nextId = AtomicInteger(6)

    private val products = ConcurrentHashMap(
        mapOf(
            "1" to Product(id = "1", name = "Mechanical Keyboard", price = 129.99),
            "2" to Product(id = "2", name = "USB-C Hub", price = 49.99),
            "3" to Product(id = "3", name = "27\" 4K Monitor", price = 399.99),
            "4" to Product(id = "4", name = "Wireless Mouse", price = 34.99),
            "5" to Product(id = "5", name = "Laptop Stand", price = 59.99),
        )
    )

    private val carrierProducts = mapOf(
        "fedex" to listOf("1", "3"),   // Mechanical Keyboard, 27" 4K Monitor
        "ups" to listOf("2", "4"),   // USB-C Hub, Wireless Mouse
        "usps" to listOf("5"),        // Laptop Stand
    )

    fun findAll(): List<Product> = products.values.toList()

    fun findById(id: String): Product? = products[id]

    fun save(product: Product): Product {
        products[product.id!!] = product
        return product
    }

    fun delete(id: String): Boolean = products.remove(id) != null

    fun nextId(): String = nextId.getAndIncrement().toString()

    var productsByCarrierCallCount = 0
    fun productsByCarrier(carrierId: String): List<Product> {
        productsByCarrierCallCount++
        return carrierProducts[carrierId]
            ?.mapNotNull { findById(it) }
            ?: emptyList()
    }

    fun productsByCarriers(carrierIds: Set<String>): Map<String, List<Product>> =
        carrierIds.associateWith { carrierId ->
            carrierProducts[carrierId]
                ?.mapNotNull { findById(it) }
                ?: emptyList()
        }
}
