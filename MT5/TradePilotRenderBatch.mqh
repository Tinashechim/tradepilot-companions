#ifndef TP_RENDER_BATCH
#define TP_RENDER_BATCH
// Publish each label's final text/style once per panel refresh.
bool tpr_batch=false;
string tpr_names[],tpr_text[];int tpr_props[];long tpr_numbers[];bool tpr_strings[];
int TPR_Find(string name,int prop){for(int i=ArraySize(tpr_names)-1;i>=0;i--)if(tpr_names[i]==name&&tpr_props[i]==prop)return i;return -1;}
int TPR_Add(string name,int prop){int i=TPR_Find(name,prop);if(i>=0)return i;i=ArraySize(tpr_names);ArrayResize(tpr_names,i+1);ArrayResize(tpr_props,i+1);ArrayResize(tpr_text,i+1);ArrayResize(tpr_numbers,i+1);ArrayResize(tpr_strings,i+1);tpr_names[i]=name;tpr_props[i]=prop;return i;}
bool TPR_Label(long chart,string name){return tpr_batch&&chart==0&&ObjectFind(0,name)>=0&&(ENUM_OBJECT)ObjectGetInteger(0,name,OBJPROP_TYPE)==OBJ_LABEL;}
bool TPR_SetInteger(long chart,string name,ENUM_OBJECT_PROPERTY_INTEGER prop,long value){if(TPR_Label(chart,name)&&(prop==OBJPROP_COLOR||prop==OBJPROP_FONTSIZE||prop==OBJPROP_XDISTANCE||prop==OBJPROP_YDISTANCE||prop==OBJPROP_ANCHOR||prop==OBJPROP_TIMEFRAMES)){int i=TPR_Add(name,(int)prop);tpr_numbers[i]=value;tpr_strings[i]=false;return true;}return ObjectSetInteger(chart,name,prop,value);}
bool TPR_SetInteger(long chart,string name,ENUM_OBJECT_PROPERTY_INTEGER prop,int modifier,long value){return ObjectSetInteger(chart,name,prop,modifier,value);}
bool TPR_SetString(long chart,string name,ENUM_OBJECT_PROPERTY_STRING prop,string value){if(TPR_Label(chart,name)&&prop==OBJPROP_TEXT){int i=TPR_Add(name,(int)prop);tpr_text[i]=value;tpr_strings[i]=true;return true;}return ObjectSetString(chart,name,prop,value);}
string TPR_GetString(long chart,string name,ENUM_OBJECT_PROPERTY_STRING prop,int modifier=0){int i=TPR_Find(name,(int)prop);if(tpr_batch&&chart==0&&prop==OBJPROP_TEXT&&i>=0&&tpr_strings[i])return tpr_text[i];return ObjectGetString(chart,name,prop,modifier);}
long TPR_GetInteger(long chart,string name,ENUM_OBJECT_PROPERTY_INTEGER prop,int modifier=0){int i=TPR_Find(name,(int)prop);if(tpr_batch&&chart==0&&(prop==OBJPROP_COLOR||prop==OBJPROP_FONTSIZE||prop==OBJPROP_XDISTANCE||prop==OBJPROP_YDISTANCE||prop==OBJPROP_ANCHOR||prop==OBJPROP_TIMEFRAMES)&&i>=0&&!tpr_strings[i])return tpr_numbers[i];return ObjectGetInteger(chart,name,prop,modifier);}
void TPR_Begin(){ArrayResize(tpr_names,0);ArrayResize(tpr_props,0);tpr_batch=true;}
void TPR_End(){tpr_batch=false;for(int i=0;i<ArraySize(tpr_names);i++){if(ObjectFind(0,tpr_names[i])<0)continue;if(tpr_strings[i]){if(ObjectGetString(0,tpr_names[i],(ENUM_OBJECT_PROPERTY_STRING)tpr_props[i])!=tpr_text[i])ObjectSetString(0,tpr_names[i],(ENUM_OBJECT_PROPERTY_STRING)tpr_props[i],tpr_text[i]);}else if(ObjectGetInteger(0,tpr_names[i],(ENUM_OBJECT_PROPERTY_INTEGER)tpr_props[i])!=tpr_numbers[i])ObjectSetInteger(0,tpr_names[i],(ENUM_OBJECT_PROPERTY_INTEGER)tpr_props[i],tpr_numbers[i]);}}
#define ObjectSetInteger TPR_SetInteger
#define ObjectSetString TPR_SetString
#define ObjectGetInteger TPR_GetInteger
#define ObjectGetString TPR_GetString
#endif
