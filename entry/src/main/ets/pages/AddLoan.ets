// 欠条本 · 新增借款页
// 录入：借款人、金额（元）、日期（日期选择器）、备注
import { common } from '@kit.AbilityKit';
import { promptAction, router } from '@kit.ArkUI';
import { DbManager } from '../database/DbManager';
import { LoanDao } from '../database/LoanDao';
import { yuanToCents, nowText, todayText, centsToYuanText, Loan } from '../model/LoanModels';

@Entry
@Component
struct AddLoan {
  @State person: string = '';
  @State amountText: string = '';
  @State note: string = '';
  @State loanDate: string = todayText();
  @State saving: boolean = false;
  @State errorText: string = '';
  @State editId: number = 0;   // >0 表示编辑已有借款
  @State isEdit: boolean = false;

  aboutToAppear(): void {
    const params = router.getParams() as Record<string, Object>;
    if (params) {
      const id: Object = params['loanId'];
      if (typeof id === 'number' && id > 0) {
        // 编辑模式：回填原记录
        this.editId = id;
        this.isEdit = true;
        this.loadForEdit();
      } else {
        // 从人员详情页进入：预填借款人
        const pn: Object = params['person'];
        if (typeof pn === 'string' && pn.length > 0) {
          this.person = pn;
        }
      }
    }
  }

  // 编辑模式：读取原记录回填表单
  private async loadForEdit(): Promise<void> {
    try {
      const ctx = getContext(this) as common.UIAbilityContext;
      await DbManager.getInstance().init(ctx);
      const loan: Loan | null = await this.loanDao.getLoanById(this.editId);
      if (loan === null) {
        this.errorText = '未找到这条借款';
        return;
      }
      this.person = loan.person;
      this.amountText = centsToYuanText(loan.amountCents);
      this.loanDate = loan.loanDate;
      this.note = loan.note;
    } catch (e) {
      this.errorText = `读取失败: ${(e as Error).message}`;
    }
  }

  private loanDao: LoanDao = new LoanDao();

  private pickDate(): void {
    DatePickerDialog.show({
      start: new Date(2000, 0, 1),
      end: new Date(2100, 11, 31),
      selected: new Date(this.loanDate),
      onDateAccept: (value: Date) => {
        const m: number = value.getMonth() + 1;
        const d: number = value.getDate();
        const mm: string = m < 10 ? `0${m}` : `${m}`;
        const dd: string = d < 10 ? `0${d}` : `${d}`;
        this.loanDate = `${value.getFullYear()}-${mm}-${dd}`;
      }
    });
  }

  private async save(): Promise<void> {
    if (this.saving) {
      return;
    }
    const person: string = this.person.trim();
    if (person.length === 0) {
      this.errorText = '请填写借款人';
      return;
    }
    const amountOk: boolean = /^\d+(\.\d{1,2})?$/.test(this.amountText);
    if (!amountOk) {
      this.errorText = '金额格式不对，示例：500 或 1234.56';
      return;
    }
    const cents: number = yuanToCents(parseFloat(this.amountText));
    if (cents <= 0) {
      this.errorText = '金额至少 0.01 元';
      return;
    }
    this.saving = true;
    this.errorText = '';
    try {
      const ctx = getContext(this) as common.UIAbilityContext;
      await DbManager.getInstance().init(ctx);
      if (this.isEdit) {
        await this.loanDao.updateLoan(this.editId, person, cents, this.loanDate, this.note.trim());
      } else {
        await this.loanDao.insertLoan(person, cents, this.loanDate, this.note.trim(), nowText());
      }
      promptAction.showToast({ message: this.isEdit ? '已更新' : '已保存' });
      router.back();
    } catch (e) {
      this.errorText = `保存失败: ${(e as Error).message}`;
    } finally {
      this.saving = false;
    }
  }

  build() {
    Column() {
      // 顶栏
      Row() {
        Text('←')
          .fontSize(24)
          .fontColor($r('app.color.text_primary'))
          .onClick(() => {
            router.back();
          })
          .padding(8)
        Text(this.isEdit ? '编辑借款' : '新增借款')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        Text('  ') // 占位，让标题居中
          .fontSize(24)
          .padding(8)
      }
      .width('100%')
      .padding({ left: 8, right: 8, top: 8 })

      Column({ space: 18 }) {
        // 借款人
        Column() {
          Text('借款人')
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
          TextInput({ placeholder: '借给谁？', text: this.person })
            .onChange((v: string) => {
              this.person = v;
            })
            .fontSize(16)
            .backgroundColor($r('app.color.bg_input'))
            .fontColor($r('app.color.text_primary'))
            .placeholderColor($r('app.color.text_tertiary'))
            .margin({ top: 6 })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)

        // 金额
        Column() {
          Text('金额（元）')
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
          TextInput({ placeholder: '0.00', text: this.amountText })
            .type(InputType.NUMBER_DECIMAL)
            .onChange((v: string) => {
              this.amountText = v;
            })
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .backgroundColor($r('app.color.bg_input'))
            .fontColor($r('app.color.text_primary'))
            .placeholderColor($r('app.color.text_tertiary'))
            .margin({ top: 6 })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)

        // 日期
        Row() {
          Text('借款日期')
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
          Blank()
          Text(this.loanDate)
            .fontSize(16)
            .fontColor($r('app.color.accent'))
          Text(' 📅')
            .fontSize(14)
        }
        .width('100%')
        .padding(14)
        .borderRadius(12)
        .backgroundColor($r('app.color.bg_input'))
        .onClick(() => {
          this.pickDate();
        })

        // 备注
        Column() {
          Text('备注')
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
          TextArea({ placeholder: '选填，如：备用金、周转', text: this.note })
            .onChange((v: string) => {
              this.note = v;
            })
            .fontSize(16)
            .height(80)
            .backgroundColor($r('app.color.bg_input'))
            .fontColor($r('app.color.text_primary'))
            .placeholderColor($r('app.color.text_tertiary'))
            .margin({ top: 6 })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)

        if (this.errorText !== '') {
          Text(this.errorText)
            .fontSize(13)
            .fontColor($r('app.color.danger'))
            .width('100%')
        }

        // 保存
        Button(this.saving ? '保存中…' : '保存')
          .width('100%')
          .height(48)
          .fontSize(17)
          .enabled(!this.saving)
          .onClick(() => {
            this.save();
          })
      }
      .width('100%')
      .layoutWeight(1)
      .padding({ left: 20, right: 20, top: 16 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_card'))
  }
}
