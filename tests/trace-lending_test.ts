import { Clarinet, Tx, Chain, Account, types } from 'https://deno.land/x/clarinet@v1.5.0/index.ts';
import { assertEquals } from 'https://deno.land/std@0.170.0/testing/asserts.ts';

Clarinet.test({
  name: "trace-lending: Loan Creation Flow",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get('deployer')!;
    const borrower = accounts.get('wallet_1')!;
    const lender = accounts.get('wallet_2')!;

    // Create a loan
    let block = chain.mineBlock([
      Tx.contractCall('trace-lending', 'create-loan', [
        types.uint(1000),    // total amount
        types.uint(50),       // interest rate (5%)
        types.uint(50000),    // loan term (blocks)
        types.uint(2500),     // collateral amount
        types.uint(500)       // liquidation threshold
      ], borrower.address)
    ]);

    // Validate loan creation
    assertEquals(block.height, 2);
    assertEquals(block.receipts.length, 1);
    block.receipts[0].result.expectOk().expectUint(1);
  }
});

Clarinet.test({
  name: "trace-lending: Loan Funding and Repayment",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get('deployer')!;
    const borrower = accounts.get('wallet_1')!;
    const lender = accounts.get('wallet_2')!;

    // Create a loan
    let block = chain.mineBlock([
      Tx.contractCall('trace-lending', 'create-loan', [
        types.uint(1000),    // total amount
        types.uint(50),       // interest rate (5%)
        types.uint(50000),    // loan term (blocks)
        types.uint(2500),     // collateral amount
        types.uint(500)       // liquidation threshold
      ], borrower.address)
    ]);

    // Fund the loan
    block = chain.mineBlock([
      Tx.contractCall('trace-lending', 'fund-loan', [
        types.uint(1)
      ], lender.address)
    ]);

    // Validate loan funding
    assertEquals(block.receipts.length, 1);
    block.receipts[0].result.expectOk().expectBool(true);

    // Repay loan
    block = chain.mineBlock([
      Tx.contractCall('trace-lending', 'repay-loan', [
        types.uint(1),
        types.uint(1100)  // Principal + interest
      ], borrower.address)
    ]);

    // Validate loan repayment
    assertEquals(block.receipts.length, 1);
    block.receipts[0].result.expectOk().expectBool(true);
  }
});

Clarinet.test({
  name: "trace-lending: Loan Liquidation Scenario",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get('deployer')!;
    const borrower = accounts.get('wallet_1')!;
    const lender = accounts.get('wallet_2')!;

    // Create a loan
    let block = chain.mineBlock([
      Tx.contractCall('trace-lending', 'create-loan', [
        types.uint(1000),    // total amount
        types.uint(50),       // interest rate (5%)
        types.uint(50000),    // loan term (blocks)
        types.uint(2500),     // collateral amount
        types.uint(500)       // liquidation threshold
      ], borrower.address)
    ]);

    // Fund the loan
    block = chain.mineBlock([
      Tx.contractCall('trace-lending', 'fund-loan', [
        types.uint(1)
      ], lender.address)
    ]);

    // Attempt loan liquidation
    block = chain.mineBlock([
      Tx.contractCall('trace-lending', 'liquidate-loan', [
        types.uint(1)
      ], deployer.address)
    ]);

    // Validate loan liquidation failure (insufficient collateral breach)
    assertEquals(block.receipts.length, 1);
    block.receipts[0].result.expectErr().expectUint(109); // ERR-LIQUIDATION-IMPOSSIBLE
  }
});