// 欠条本 · 借款表数据访问对象（loans）
import { relationalStore } from '@kit.ArkData';
import { DbManager } from './DbManager';
import { Loan, LoanSummary, PersonSummary } from '../model/LoanModels';

export class LoanDao {
  // 新增借款，返回新记录 id
  public async insertLoan(person: string, amountCents: number,
                          loanDate: string, note: string, createdAt: string): Promise<number> {
    const bucket: relationalStore.ValuesBucket = {
      'person': person,
      'amount_cents': amountCents,
      'loan_date': loanDate,
      'note': note,
      'created_at': createdAt
    };
    return await DbManager.getInstance().getStore().insert('loans', bucket);
  }

  // 总览查询：全部借款 + 每笔的已还汇总（未还清/零还款的也会列出）
  // 已还金额 = SUM(repayments.amount_cents)，实时计算，不做冗余存储
  public async getAllSummaries(): Promise<LoanSummary[]> {
    const sql: string =
      'SELECT l.id AS id, l.person AS person, l.amount_cents AS amount_cents, ' +
      'COALESCE(SUM(r.amount_cents), 0) AS repaid_cents, ' +
      'l.loan_date AS loan_date, l.note AS note ' +
      'FROM loans l LEFT JOIN repayments r ON r.loan_id = l.id ' +
      'GROUP BY l.id ORDER BY l.created_at DESC';
    const rs: relationalStore.ResultSet =
      await DbManager.getInstance().getStore().querySql(sql);
    const list: LoanSummary[] = [];
    try {
      while (rs.goToNextRow()) {
        const item: LoanSummary = {
          id: rs.getLong(rs.getColumnIndex('id')),
          person: rs.getString(rs.getColumnIndex('person')),
          amountCents: rs.getLong(rs.getColumnIndex('amount_cents')),
          repaidCents: rs.getLong(rs.getColumnIndex('repaid_cents')),
          loanDate: rs.getString(rs.getColumnIndex('loan_date')),
          note: rs.getString(rs.getColumnIndex('note'))
        };
        list.push(item);
      }
    } finally {
      rs.close();
    }
    return list;
  }

  // 按借款人维度汇总（首页列表使用）：每人总借出/已还/笔数
  // 按待收金额降序，待收相同的按最近一次借出时间降序
  public async getPersonSummaries(): Promise<PersonSummary[]> {
    const sql: string =
      'SELECT l.person AS person, COUNT(DISTINCT l.id) AS loan_count, ' +
      'SUM(l.amount_cents) AS amount_cents, COALESCE(SUM(rr.repaid), 0) AS repaid_cents ' +
      'FROM loans l ' +
      'LEFT JOIN (SELECT loan_id, SUM(amount_cents) AS repaid FROM repayments GROUP BY loan_id) rr ' +
      'ON rr.loan_id = l.id ' +
      'GROUP BY l.person ' +
      'ORDER BY (SUM(l.amount_cents) - COALESCE(SUM(rr.repaid), 0)) DESC, MAX(l.created_at) DESC';
    const rs: relationalStore.ResultSet = await DbManager.getInstance().getStore().querySql(sql);
    const list: PersonSummary[] = [];
    try {
      while (rs.goToNextRow()) {
        const item: PersonSummary = {
          person: rs.getString(rs.getColumnIndex('person')),
          loanCount: rs.getLong(rs.getColumnIndex('loan_count')),
          amountCents: rs.getLong(rs.getColumnIndex('amount_cents')),
          repaidCents: rs.getLong(rs.getColumnIndex('repaid_cents'))
        };
        list.push(item);
      }
    } finally {
      rs.close();
    }
    return list;
  }

  // 某人的全部借款 + 已还汇总（人员详情页使用）
  public async getSummariesByPerson(person: string): Promise<LoanSummary[]> {
    const sql: string =
      'SELECT l.id AS id, l.person AS person, l.amount_cents AS amount_cents, ' +
      'COALESCE(SUM(r.amount_cents), 0) AS repaid_cents, ' +
      'l.loan_date AS loan_date, l.note AS note ' +
      'FROM loans l LEFT JOIN repayments r ON r.loan_id = l.id ' +
      'WHERE l.person = ? GROUP BY l.id ORDER BY l.created_at DESC';
    const args: Array<relationalStore.ValueType> = [person];
    const rs: relationalStore.ResultSet = await DbManager.getInstance().getStore().querySql(sql, args);
    const list: LoanSummary[] = [];
    try {
      while (rs.goToNextRow()) {
        const item: LoanSummary = {
          id: rs.getLong(rs.getColumnIndex('id')),
          person: rs.getString(rs.getColumnIndex('person')),
          amountCents: rs.getLong(rs.getColumnIndex('amount_cents')),
          repaidCents: rs.getLong(rs.getColumnIndex('repaid_cents')),
          loanDate: rs.getString(rs.getColumnIndex('loan_date')),
          note: rs.getString(rs.getColumnIndex('note'))
        };
        list.push(item);
      }
    } finally {
      rs.close();
    }
    return list;
  }

  // 删除某人的全部借款及其还款记录（事务保证一致性）
  public async deleteLoansByPerson(person: string): Promise<void> {
    const store: relationalStore.RdbStore = DbManager.getInstance().getStore();
    const args: Array<relationalStore.ValueType> = [person];
    const rs: relationalStore.ResultSet = await store.querySql('SELECT id FROM loans WHERE person = ?', args);
    const ids: number[] = [];
    try {
      while (rs.goToNextRow()) {
        ids.push(rs.getLong(rs.getColumnIndex('id')));
      }
    } finally {
      rs.close();
    }
    if (ids.length === 0) {
      return;
    }
    const tx: relationalStore.Transaction = await store.createTransaction();
    try {
      for (const id of ids) {
        const predRepay: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('repayments');
        predRepay.equalTo('loan_id', id);
        await tx.delete(predRepay);

        const predLoan: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('loans');
        predLoan.equalTo('id', id);
        await tx.delete(predLoan);
      }
      await tx.commit();
    } catch (e) {
      try {
        await tx.rollback();
      } catch (re) {
        // ignore
      }
      throw e as Error;
    }
  }

  // 查询单笔借款（编辑页回填用）
  public async getLoanById(loanId: number): Promise<Loan | null> {
    const args: Array<relationalStore.ValueType> = [loanId];
    const rs: relationalStore.ResultSet = await DbManager.getInstance().getStore()
      .querySql('SELECT id, person, amount_cents, loan_date, note FROM loans WHERE id = ?', args);
    let item: Loan | null = null;
    try {
      if (rs.goToNextRow()) {
        item = {
          id: rs.getLong(rs.getColumnIndex('id')),
          person: rs.getString(rs.getColumnIndex('person')),
          amountCents: rs.getLong(rs.getColumnIndex('amount_cents')),
          loanDate: rs.getString(rs.getColumnIndex('loan_date')),
          note: rs.getString(rs.getColumnIndex('note'))
        };
      }
    } finally {
      rs.close();
    }
    return item;
  }

  // 单笔借款 + 已还汇总（详情页使用）
  public async getSummaryById(loanId: number): Promise<LoanSummary | null> {
    const sql: string =
      'SELECT l.id AS id, l.person AS person, l.amount_cents AS amount_cents, ' +
      'COALESCE(SUM(r.amount_cents), 0) AS repaid_cents, ' +
      'l.loan_date AS loan_date, l.note AS note ' +
      'FROM loans l LEFT JOIN repayments r ON r.loan_id = l.id ' +
      'WHERE l.id = ? GROUP BY l.id';
    const args: Array<relationalStore.ValueType> = [loanId];
    const rs: relationalStore.ResultSet = await DbManager.getInstance().getStore().querySql(sql, args);
    let item: LoanSummary | null = null;
    try {
      if (rs.goToNextRow()) {
        item = {
          id: rs.getLong(rs.getColumnIndex('id')),
          person: rs.getString(rs.getColumnIndex('person')),
          amountCents: rs.getLong(rs.getColumnIndex('amount_cents')),
          repaidCents: rs.getLong(rs.getColumnIndex('repaid_cents')),
          loanDate: rs.getString(rs.getColumnIndex('loan_date')),
          note: rs.getString(rs.getColumnIndex('note'))
        };
      }
    } finally {
      rs.close();
    }
    return item;
  }

  // 更新借款（编辑保存）
  public async updateLoan(loanId: number, person: string, amountCents: number,
                          loanDate: string, note: string): Promise<void> {
    const bucket: relationalStore.ValuesBucket = {
      'person': person,
      'amount_cents': amountCents,
      'loan_date': loanDate,
      'note': note
    };
    const pred: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('loans');
    pred.equalTo('id', loanId);
    await DbManager.getInstance().getStore().update(bucket, pred);
  }

  // 删除借款，同时删除其全部还款记录（事务保证一致性）
  // 注：API 14+ 使用 createTransaction 获取事务对象，commit/rollback 均为异步
  public async deleteLoan(loanId: number): Promise<void> {
    const store: relationalStore.RdbStore = DbManager.getInstance().getStore();
    const tx: relationalStore.Transaction = await store.createTransaction();
    try {
      const predRepay: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('repayments');
      predRepay.equalTo('loan_id', loanId);
      await tx.delete(predRepay);

      const predLoan: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('loans');
      predLoan.equalTo('id', loanId);
      await tx.delete(predLoan);

      await tx.commit();
    } catch (e) {
      // 回滚失败不掩盖原始异常
      try {
        await tx.rollback();
      } catch (re) {
        // ignore
      }
      throw e as Error;
    }
  }
}
