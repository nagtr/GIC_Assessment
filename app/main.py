from fastapi import FastAPI, HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session
from decimal import Decimal

from .db import SessionLocal, init_db
from .models import Account
from .schemas import CreateAccountReq, BalanceResp, AmountReq, MessageResp, AccountResp

app = FastAPI(title="Banking API", version="1.0.0")

@app.on_event("startup")
def on_startup():
    init_db()

@app.get("/healthz")
def healthz():
    return {"status": "ok"}

@app.post("/accounts", response_model=AccountResp)
def create_account(req: CreateAccountReq):
    with SessionLocal() as session:
        existing = session.get(Account, req.account_id)
        if existing:
            raise HTTPException(status_code=409, detail="Account already exists")
        acct = Account(account_id=req.account_id, balance=Decimal(req.initial_balance))
        session.add(acct)
        session.commit()
        session.refresh(acct)
        return AccountResp(account_id=acct.account_id, balance=acct.balance)

@app.get("/accounts/{account_id}/balance", response_model=BalanceResp)
def get_balance(account_id: str):
    with SessionLocal() as session:
        acct = session.get(Account, account_id)
        if not acct:
            raise HTTPException(status_code=404, detail="Account not found")
        return BalanceResp(account_id=acct.account_id, balance=acct.balance)

@app.post("/accounts/{account_id}/deposit", response_model=AccountResp)
def deposit(account_id: str, req: AmountReq):
    with SessionLocal() as session:
        with session.begin():
            acct = session.execute(
                select(Account).where(Account.account_id == account_id).with_for_update()
            ).scalar_one_or_none()
            if not acct:
                raise HTTPException(status_code=404, detail="Account not found")
            acct.balance = (acct.balance or Decimal("0.00")) + Decimal(req.amount)
            session.add(acct)
        session.refresh(acct)
        return AccountResp(account_id=acct.account_id, balance=acct.balance)

@app.post("/accounts/{account_id}/withdraw", response_model=AccountResp)
def withdraw(account_id: str, req: AmountReq):
    with SessionLocal() as session:
        with session.begin():
            acct = session.execute(
                select(Account).where(Account.account_id == account_id).with_for_update()
            ).scalar_one_or_none()
            if not acct:
                raise HTTPException(status_code=404, detail="Account not found")
            new_balance = (acct.balance or Decimal("0.00")) - Decimal(req.amount)
            if new_balance < 0:
                raise HTTPException(status_code=400, detail="Insufficient funds")
            acct.balance = new_balance
            session.add(acct)
        session.refresh(acct)
        return AccountResp(account_id=acct.account_id, balance=acct.balance)

@app.delete("/accounts/{account_id}", response_model=MessageResp)
def delete_account(account_id: str):
    with SessionLocal() as session:
        acct = session.get(Account, account_id)
        if not acct:
            raise HTTPException(status_code=404, detail="Account not found")
        session.delete(acct)
        session.commit()
        return MessageResp(message="Account deleted")
