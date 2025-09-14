from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column
from sqlalchemy import String, Numeric, DateTime, func
from decimal import Decimal
from datetime import datetime

class Base(DeclarativeBase):
    pass

class Account(Base):
    __tablename__ = "accounts"

    # Primary key as string
    account_id: Mapped[str] = mapped_column(String(64), primary_key=True)

    # Decimal balance with default
    balance: Mapped[Decimal] = mapped_column(
        Numeric(18, 2),
        nullable=False,
        default=Decimal("0.00")
    )

    # Explicit type annotation fixes your error
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now()
    )

    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        onupdate=func.now()
    )

