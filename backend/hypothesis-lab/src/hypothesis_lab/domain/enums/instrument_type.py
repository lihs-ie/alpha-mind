"""InstrumentType enumeration."""

from enum import StrEnum


class InstrumentType(StrEnum):
    """金融商品種別。"""

    ETF = "etf"
    STOCK = "stock"
