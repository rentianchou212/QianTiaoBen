// 欠条本 · 还款表数据访问对象（repayments）
import { relationalStore } from '@kit.ArkData';
import { DbManager } from './DbManager';
import { Repayment } from '../model/LoanModels';

export class RepaymentDao {
  // 记一笔还款，返回新记录 id
  public async insertRepayment(loanId: number, amountCents: number,
                               repayDate: string, note: string): Promise<number> {
    const bucket: relationalStore.ValuesBucket = {
      'loan_id': loanId,
      'amount_cents': amountCents,
      'repay_date': repayDate,
      'note': note
    };
    return await DbManager.getInstance().getStore().insert('repayments', bucket);
  }

  // 某笔借款的全部还款记录（按日期倒序，新的在前）
  public async getByLoan(loanId: number): Promise<Repayment[]> {
    const pred: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('repayments');
    pred.equalTo('loan_id', loanId).orderByDesc('repay_date').orderByDesc('id');
    const rs: relationalStore.ResultSet =
      await DbManager.getInstance().getStore().query(pred);
    const list: Repayment[] = [];
    try {
      while (rs.goToNextRow()) {
        const item: Repayment = {
          id: rs.getLong(rs.getColumnIndex('id')),
          loanId: rs.getLong(rs.getColumnIndex('loan_id')),
          amountCents: rs.getLong(rs.getColumnIndex('amount_cents')),
          repayDate: rs.getString(rs.getColumnIndex('repay_date')),
          note: rs.getString(rs.getColumnIndex('note'))
        };
        list.push(item);
      }
    } finally {
      rs.close();
    }
    return list;
  }

  // 删除单笔还款
  public async deleteRepayment(repaymentId: number): Promise<void> {
    const pred: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('repayments');
    pred.equalTo('id', repaymentId);
    await DbManager.getInstance().getStore().delete(pred);
  }
}
