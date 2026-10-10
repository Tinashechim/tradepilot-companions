#ifndef TRADEPILOT_MODE_CONVERSION
#define TRADEPILOT_MODE_CONVERSION
// Modes: 0 Cash, 1 Percentage, 2 risk multiple. Preserve the cash amount.
double TPDM_Convert(double value,int from,int to,double balance,double risk)
{
 if(!MathIsValidNumber(value)||value<=0||from<0||from>2||to<0||to>2)return -1;
 if(from==to)return value;
 if((from==1||to==1)&&(!MathIsValidNumber(balance)||balance<=0))return -1;
 if((from==2||to==2)&&(!MathIsValidNumber(risk)||risk<=0))return -1;
 double cash=from==1?balance*value/100.0:from==2?risk*value:value;
 double result=to==1?cash/balance*100.0:to==2?cash/risk:cash;
 return MathIsValidNumber(result)&&result>0?result:-1;
}
#endif
