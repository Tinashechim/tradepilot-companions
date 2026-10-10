// Read-only broker sizing checks. Never sends an order.
string tp_size_reason="",tp_size_detail="";
double tp_size_requested=0,tp_requested_margin=-1;int tp_requested_margin_check=-1;
double tp_minimum_margin=-1,tp_minimum_volume=0,tp_margin_free=0;int tp_minimum_margin_check=-1;
void TP_SizeDiagnostic(double raw,double risk,double loss,string currency)
{
 string minimum=DoubleToString(SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN),8);
 tp_size_detail="Allowed stop-loss risk: "+currency+" "+DoubleToString(risk,2)+". Stop-loss risk per lot: "+currency+" "+DoubleToString(loss,2)+". Risk-based size: "+DoubleToString(raw,8)+" lots. Broker minimum: "+minimum+" lots. ";
}

int TP_CheckMargin(string symbol,int side,double price,double volume,double &required)
{
   required=-1;
   if(!MathIsValidNumber(volume) || !MathIsValidNumber(price) || volume<=0 || price<=0) return -1;
#ifdef __MQL5__
   ResetLastError();
   if(!OrderCalcMargin((ENUM_ORDER_TYPE)side,symbol,volume,price,required) || !MathIsValidNumber(required) || required<0) return -1;
   return required<AccountInfoDouble(ACCOUNT_MARGIN_FREE) ? 1 : 0;
#else
   ResetLastError();
   double before=AccountFreeMargin(),after=AccountFreeMarginCheck(symbol,side,volume);
   int error=GetLastError();
   if(!MathIsValidNumber(before) || !MathIsValidNumber(after) || before<0) return -1;
   if(error!=0 && error!=134) return -1;
   required=MathMax(0,before-after);
   return error!=134 && after>0 ? 1 : 0;
#endif
}
double TP_AffordableLots(string symbol,int side,double price,double risk_lots)
{
   tp_size_reason="";tp_minimum_margin=-1;tp_minimum_volume=0;tp_minimum_margin_check=-1;
#ifdef __MQL5__
   tp_margin_free=AccountInfoDouble(ACCOUNT_MARGIN_FREE);
#else
   tp_margin_free=AccountFreeMargin();
#endif
   double minimum=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MIN),maximum=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MAX),step=SymbolInfoDouble(symbol,SYMBOL_VOLUME_STEP);
   if(!MathIsValidNumber(step) || !MathIsValidNumber(minimum) || !MathIsValidNumber(maximum) || step<=0 || minimum<=0 || maximum<minimum || !MathIsValidNumber(risk_lots)) {tp_size_reason="Broker lot rules pending";return -1;}
   long low=(long)MathCeil(minimum/step-1e-9),high=(long)MathFloor(MathMin(risk_lots,maximum)/step+1e-9);
   tp_size_requested=NormalizeDouble(MathMax(0,high)*step,8);tp_requested_margin=-1;tp_requested_margin_check=-1;
   if(tp_size_requested>=minimum)tp_requested_margin_check=TP_CheckMargin(symbol,side,price,tp_size_requested,tp_requested_margin);

   tp_minimum_volume=NormalizeDouble(low*step,8);
   double margin=0;int check=TP_CheckMargin(symbol,side,price,tp_minimum_volume,margin);
   tp_minimum_margin=margin;tp_minimum_margin_check=check;
   tp_size_detail+="Available free margin: "+DoubleToString(tp_margin_free,2)+". Margin for minimum "+DoubleToString(tp_minimum_volume,8)+" lots: "+(check<0?"Verification pending":DoubleToString(margin,2))+". ";
   if(high<low) {tp_size_reason="Below minimum lot";return 0;}
   if(check<0) {tp_size_reason="Margin not verified";return -1;}
   if(check==0) {tp_size_reason="Insufficient free margin";return 0;}
   long best=low;
   while(low<=high) {
      long mid=low+(high-low)/2;
      check=TP_CheckMargin(symbol,side,price,NormalizeDouble(mid*step,8),margin);
      if(check<0) {tp_size_reason="Margin not verified";return -1;}
      if(check==1) {best=mid;low=mid+1;} else high=mid-1;
   }
   return NormalizeDouble(best*step,8);
}

