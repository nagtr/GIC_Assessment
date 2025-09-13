from pydantic import BaseModel, Field, condecimal
from decimal import Decimal

Money = condecimal(max_digits=18, decimal_places=2, gt=0)

class CreateAccountReq(BaseModel):
    account_id: str = Field(min_length=1, max_length=64)
    initial_balance: condecimal(max_digits=18, decimal_places=2, ge=0) = Decimal("0.00")

class BalanceResp(BaseModel):
    account_id: str
    balance: Decimal

class AmountReq(BaseModel):
    amount: Money

class MessageResp(BaseModel):
    message: str

class AccountResp(BaseModel):
    account_id: str
    balance: Decimal
