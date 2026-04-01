package com.example.catalog

import java.util.Base64

fun encodeCursor(index: Int): String = Base64.getEncoder().encodeToString("cursor:$index".toByteArray())

fun decodeCursor(cursor: String): Int =
    Base64
        .getDecoder()
        .decode(cursor)
        .toString(Charsets.UTF_8)
        .removePrefix("cursor:")
        .toInt()
