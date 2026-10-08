// Read-only broker sizing checks. Never sends an order.
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
   double minimum=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MIN),maximum=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MAX),step=SymbolInfoDouble(symbol,SYMBOL_VOLUME_STEP);
   if(!MathIsValidNumber(step) || !MathIsValidNumber(minimum) || !MathIsValidNumber(maximum) || step<=0 || minimum<=0 || maximum<minimum || !MathIsValidNumber(risk_lots)) return -1;
   long low=(long)MathCeil(minimum/step-1e-9),high=(long)MathFloor(MathMin(risk_lots,maximum)/step+1e-9);
   if(high<low) return 0;
   double margin=0;int check=TP_CheckMargin(symbol,side,price,NormalizeDouble(low*step,8),margin);
   if(check<0) return -1;
   if(check==0) return 0;
   long best=low;
   while(low<=high) {
      long mid=low+(high-low)/2;
      check=TP_CheckMargin(symbol,side,price,NormalizeDouble(mid*step,8),margin);
      if(check<0) return -1;
      if(check==1) {best=mid;low=mid+1;} else high=mid-1;
   }
   return NormalizeDouble(best*step,8);
}
