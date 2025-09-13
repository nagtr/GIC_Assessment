from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column
from sqlalchemy import String, Numeric, DateTime, func
from decimal import Decimal

class Base(DeclarativeBase):
    pass

class Account(Base):
    __tablename__ = "accounts"
    account_id: Mapped[str] = mapped_column(String(64), primary_key=True)
    balance: Mapped[Decimal] = mapped_column(Numeric(18, 2), nullable=False, default=Decimal("0.00"))
    created_at: Mapped = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped = mapped_column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())
