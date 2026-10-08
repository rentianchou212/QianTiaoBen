// 展示按借款人汇总的列表 + 顶部全局汇总（总借出/已收回/待收回）
// 交互：点右下角 + 新增借款；点人员卡片进该人详情；长按人员卡片删除其全部借款
import { common } from '@kit.AbilityKit';
import { promptAction, router } from '@kit.ArkUI';
import { DbManager } from '../database/DbManager';
import { LoanDao } from '../database/LoanDao';
import { pasteboard } from '@kit.BasicServicesKit';
import { RepaymentDao } from '../database/RepaymentDao';
import { PersonSummary, LoanSummary, Repayment, centsToYuanText, todayText } from '../model/LoanModels';

@Entry
@Component
struct Index {
  @State persons: PersonSummary[] = [];
  @State loaded: boolean = false;
  @State errorMsg: string = '';

  @State exporting: boolean = false;
  private loanDao: LoanDao = new LoanDao();
  private repayDao: RepaymentDao = new RepaymentDao();

  aboutToAppear(): void {
    this.loadPersons();
  }

  // 从新增/详情页返回时刷新列表
  onPageShow(): void {
    this.loadPersons();
  }

  // 汇总：总借出（分）
  private totalLentCents(): number {
    let sum: number = 0;
    for (const s of this.persons) {
      sum += s.amountCents;
    }
    return sum;
  }

  // 汇总：已收回（分），多还的部分不计入
  private totalRepaidCents(): number {
    let sum: number = 0;
    for (const s of this.persons) {
      sum += Math.min(s.repaidCents, s.amountCents);
    }
    return sum;
  }

  private async loadPersons(): Promise<void> {
    try {
      const ctx = getContext(this) as common.UIAbilityContext;
      await DbManager.getInstance().init(ctx);
      this.persons = await this.loanDao.getPersonSummaries();
      this.loaded = true;
      this.errorMsg = '';
    } catch (e) {
      this.errorMsg = `数据库异常: ${(e as Error).message}`;
      this.loaded = true;
    }
  }

  // 删除某人全部借款（含还款记录）
  private async removePerson(person: string): Promise<void> {
    try {
      await this.loanDao.deleteLoansByPerson(person);
      promptAction.showToast({ message: '已删除' });
      await this.loadPersons();
    } catch (e) {
      promptAction.showToast({ message: `删除失败: ${(e as Error).message}` });
    }
  }

  // 标题下的日期：如「9月28日 周日」
  private todayLabel(): string {
    const d = new Date();
    const weeks: string[] = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];
    return `${d.getMonth() + 1}月${d.getDate()}日 ${weeks[d.getDay()]}`;
  }

  // 导出：按人生成文本账单并复制到剪贴板
  private async exportData(): Promise<void> {
    if (this.exporting) {
      return;
    }
    if (this.persons.length === 0) {
      promptAction.showToast({ message: '暂无借款数据可导出' });
      return;
    }
    this.exporting = true;
    try {
      const lines: string[] = [];
      lines.push(`【欠条本】账单 ${todayText()}`);
      lines.push('================================');
      let totalLent: number = 0;
      let totalRepaid: number = 0;
      for (const p of this.persons) {
        const personRepaid: number = Math.min(p.repaidCents, p.amountCents);
        const personPending: number = p.amountCents - personRepaid;
        lines.push('');
        lines.push(`■ ${p.person}（共 ${p.loanCount} 笔）`);
        lines.push(`  借出 ¥${centsToYuanText(p.amountCents)} | 已还 ¥${centsToYuanText(personRepaid)} | 待收 ¥${centsToYuanText(personPending)}`);
        totalLent += p.amountCents;
        totalRepaid += personRepaid;
        const loans: LoanSummary[] = await this.loanDao.getSummariesByPerson(p.person);
        let no: number = 1;
        for (const loan of loans) {
          const repaid: number = Math.min(loan.repaidCents, loan.amountCents);
          const pending: number = loan.amountCents - repaid;
          let row: string = `  ${no}. ${loan.loanDate} 借 ¥${centsToYuanText(loan.amountCents)}`;
          if (repaid > 0) {
            row += `（已还 ¥${centsToYuanText(repaid)}，待收 ¥${centsToYuanText(pending)}）`;
          } else {
            row += '（未还）';
          }
          if (loan.note.length > 0) {
            row += `｜备注：${loan.note}`;
          }
          lines.push(row);
          const reps: Repayment[] = await this.repayDao.getByLoan(loan.id);
          for (const r of reps) {
            let rrow: string = `     ↳ 还款 ${r.repayDate} ¥${centsToYuanText(r.amountCents)}`;
            if (r.note.length > 0) {
              rrow += `｜备注：${r.note}`;
            }
            lines.push(rrow);
          }
          no++;
        }
      }
      lines.push('');
      lines.push('================================');
      lines.push(`合计：总借出 ¥${centsToYuanText(totalLent)}，已收回 ¥${centsToYuanText(totalRepaid)}，待收回 ¥${centsToYuanText(totalLent - totalRepaid)}`);
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, lines.join('\n'));
      await pasteboard.getSystemPasteboard().setData(data);
      promptAction.showToast({ message: '账单已复制到剪贴板，可粘贴保存' });
    } catch (e) {
      promptAction.showToast({ message: `导出失败: ${(e as Error).message}` });
    } finally {
      this.exporting = false;
    }
  }

  private confirmDeletePerson(s: PersonSummary): void {
    AlertDialog.show({
      message: `删除「${s.person}」的全部 ${s.loanCount} 笔借款？\n其全部还款记录会一并删除。`,
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '删除',
        fontColor: $r('app.color.danger'),
        action: () => {
          this.removePerson(s.person);
        }
      }
    });
  }

  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Column() {
        // 标题（个性设计：红色¥标识 + 双色标题 + 日期）+ 导出入口
        Row() {
          Text('¥')
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
            .width(32)
            .height(32)
            .textAlign(TextAlign.Center)
            .borderRadius(9)
            .backgroundColor($r('app.color.danger'))
            .margin({ right: 10 })
          Column() {
            Text() {
              Span('欠条')
                .fontSize(24)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_primary'))
              Span('本')
                .fontSize(24)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.danger'))
            }
            Text(this.todayLabel())
              .fontSize(12)
              .fontColor($r('app.color.text_tertiary'))
              .margin({ top: 2 })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          Text('导出')
            .fontSize(16)
            .fontColor($r('app.color.accent'))
            .padding({ left: 12, right: 4, top: 8, bottom: 8 })
            .onClick(() => {
              this.exportData();
            })
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 16, bottom: 12 })

        // 汇总卡片（全局：所有借款人合计）
        Row() {
          Column() {
            Text('待收回')
              .fontSize(13)
              .fontColor($r('app.color.text_tertiary'))
            Text(`¥${centsToYuanText(this.totalLentCents() - this.totalRepaidCents())}`)
              .fontSize(26)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.totalLentCents() - this.totalRepaidCents() > 0 ? $r('app.color.danger') : $r('app.color.text_primary'))
              .margin({ top: 4 })
          }
          .layoutWeight(1)

          Column() {
            Text('总借出')
              .fontSize(13)
              .fontColor($r('app.color.text_tertiary'))
            Text(`¥${centsToYuanText(this.totalLentCents())}`)
              .fontSize(18)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
              .margin({ top: 8 })
          }
          .layoutWeight(1)

          Column() {
            Text('已收回')
              .fontSize(13)
              .fontColor($r('app.color.text_tertiary'))
            Text(`¥${centsToYuanText(this.totalRepaidCents())}`)
              .fontSize(18)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.success'))
              .margin({ top: 8 })
          }
          .layoutWeight(1)
        }
        .width('92%')
        .padding(16)
        .borderRadius(16)
        .backgroundColor($r('app.color.bg_card'))

        if (this.errorMsg !== '') {
          Text(this.errorMsg)
            .fontSize(14)
            .fontColor($r('app.color.danger'))
            .margin({ top: 20 })
        } else if (this.loaded && this.persons.length === 0) {
          // 空状态
          Column() {
            Text('📖')
              .fontSize(48)
            Text('还没有借出记录')
              .fontSize(16)
              .fontColor($r('app.color.text_tertiary'))
              .margin({ top: 12 })
            Text('点右下角 + 记第一笔')
              .fontSize(13)
              .fontColor($r('app.color.text_quaternary'))
              .margin({ top: 6 })
          }
          .width('100%')
          .margin({ top: 80 })
        } else {
          // 小节标题
          Row() {
            Text('按借款人统计')
              .fontSize(13)
              .fontColor($r('app.color.text_tertiary'))
            Blank()
            Text(this.persons.length > 0 ? `共 ${this.persons.length} 人 · 长按删除` : '共 0 人')
              .fontSize(12)
              .fontColor($r('app.color.text_quaternary'))
          }
          .width('92%')
          .margin({ top: 16, bottom: 8 })

          // 按人维度列表
          List() {
            ForEach(this.persons, (s: PersonSummary) => {
              ListItem() {
                Column() {
                  Row() {
                    Text(s.person)
                      .fontSize(18)
                      .fontWeight(FontWeight.Medium)
                      .fontColor($r('app.color.text_primary'))
                      .layoutWeight(1)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    if (s.amountCents - s.repaidCents <= 0) {
                      Text('已还清')
                        .fontSize(12)
                        .fontColor($r('app.color.success'))
                        .padding({ left: 8, right: 8, top: 2, bottom: 2 })
                        .borderRadius(10)
                        .backgroundColor($r('app.color.badge_bg'))
                    }
                    Text(`¥${centsToYuanText(s.amountCents)}`)
                      .fontSize(18)
                      .fontWeight(FontWeight.Bold)
                      .fontColor($r('app.color.text_primary'))
                      .margin({ left: 8 })
                  }
                  .width('100%')

                  Progress({ value: Math.min(s.repaidCents, s.amountCents), total: s.amountCents, type: ProgressType.Linear })
                    .width('100%')
                    .height(6)
                    .margin({ top: 10 })
                    .color($r('app.color.success'))

                  Row() {
                    Text(`已还 ¥${centsToYuanText(s.repaidCents)} · 待收 ¥${centsToYuanText(Math.max(0, s.amountCents - s.repaidCents))}`)
                      .fontSize(13)
                      .fontColor($r('app.color.text_tertiary'))
                    Blank()
                    Text(`${s.loanCount} 笔借款`)
                      .fontSize(13)
                      .fontColor($r('app.color.text_quaternary'))
                  }
                  .width('100%')
                  .margin({ top: 8 })
                }
                .width('100%')
                .padding(14)
                .borderRadius(12)
                .backgroundColor($r('app.color.bg_card'))
                .margin({ bottom: 10 })
                .onClick(() => {
                  const p: Record<string, string> = { 'person': s.person };
                  router.pushUrl({ url: 'pages/PersonDetail', params: p });
                })
                .gesture(LongPressGesture().onAction(() => {
                  this.confirmDeletePerson(s);
                }))
              }
            }, (s: PersonSummary) => `${s.person}_${s.amountCents}_${s.repaidCents}`)
          }
          .width('92%')
          .layoutWeight(1)
          .margin({ top: 0 })
          .scrollBar(BarState.Off)
        }
      }
      .width('100%')
      .height('100%')

      // 新增按钮（FAB）
      Button('+')
        .width(56)
        .height(56)
        .fontSize(28)
        .type(ButtonType.Circle)
        .backgroundColor($r('app.color.accent'))
        .margin(24)
        .onClick(() => {
          router.pushUrl({ url: 'pages/AddLoan' });
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_page'))
  }
}
