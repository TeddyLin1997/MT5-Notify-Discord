#property description "監控 MT5 帳戶所有交易事件並推送至 Discord"

//--- 輸入參數
input string    API_URL = "your-api-url-here";  // 後端 API URL
input string    API_TOKEN = "your-super-secret-token-here";                     // API 認證 Token
input int       MAX_RETRY = 3;                                                   // HTTP 重試次數
input int       RETRY_DELAY_MS = 1000;                                          // 重試延遲（毫秒）
input bool      ENABLE_LOGGING = true;                                          // 啟用本地日誌

//--- 全局變數
datetime        lastEventTime = 0;
ulong           lastDealTicket = 0;
ulong           lastOrderTicket = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                     |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- 檢查 WebRequest 權限
   if(!TerminalInfoInteger(TERMINAL_DLLS_ALLOWED))
   {
      Alert("請在 MT5 設置中允許 DLL 呼叫！");
      return(INIT_FAILED);
   }

   //--- 檢查 API URL 設定
   if(StringLen(API_URL) == 0)
   {
      Alert("請設置 API_URL 參數！");
      return(INIT_FAILED);
   }

   //--- 添加 URL 到白名單
   string hostname = ExtractHostname(API_URL);
   if(StringLen(hostname) > 0)
   {
      Print("請在 MT5 選項 -> Expert Advisors -> WebRequest 中添加: ", hostname);
   }

   Print("MT5 Notify Monitor 啟動成功！");
   Print("監控帳戶: ", AccountInfoInteger(ACCOUNT_LOGIN));
   Print("API URL: ", API_URL);

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                   |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("MT5 Notify Monitor 停止，原因: ", reason);
}

//+------------------------------------------------------------------+
//| Trade transaction event handler                                    |
//+------------------------------------------------------------------+
void OnTradeTransaction(
   const MqlTradeTransaction& trans,
   const MqlTradeRequest& request,
   const MqlTradeResult& result
)
{
   //--- 忽略無效交易
   if(trans.symbol == "" || trans.symbol == NULL)
      return;

   //--- 根據交易類型處理事件
   switch(trans.type)
   {
      case TRADE_TRANSACTION_DEAL_ADD:
         HandleDealAdd(trans, request);
         break;

      case TRADE_TRANSACTION_ORDER_ADD:
         HandleOrderAdd(trans, request);
         break;

      case TRADE_TRANSACTION_ORDER_UPDATE:
         HandleOrderUpdate(trans, request);
         break;

      case TRADE_TRANSACTION_ORDER_DELETE:
         HandleOrderDelete(trans, request);
         break;

      default:
         // 忽略其他交易類型（如 REQUEST）
         break;
   }
}

//+------------------------------------------------------------------+
//| 處理 Deal 事件（開倉/平倉）                                          |
//+------------------------------------------------------------------+
void HandleDealAdd(const MqlTradeTransaction& trans, const MqlTradeRequest& request)
{
   //--- 防止重複處理
   if(trans.deal == lastDealTicket)
      return;

   lastDealTicket = trans.deal;

   //--- 獲取 Deal 資訊
   if(!HistoryDealSelect(trans.deal))
   {
      LogMessage("無法選擇 Deal: " + IntegerToString(trans.deal));
      return;
   }

   long dealEntry = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);

   //--- 判斷開倉或平倉
   string eventType = "";
   if(dealEntry == DEAL_ENTRY_IN)
   {
      eventType = "ORDER_OPEN";
   }
   else if(dealEntry == DEAL_ENTRY_OUT)
   {
      //--- 檢查是否為部分平倉
      double dealVolume = HistoryDealGetDouble(trans.deal, DEAL_VOLUME);

      // 獲取原始持倉信息（簡化處理，實際需更複雜邏輯）
      if(CheckIfPartialClose(trans.symbol, dealVolume))
         eventType = "PARTIAL_CLOSE";
      else
         eventType = "ORDER_CLOSE";
   }
   else
   {
      return; // 忽略其他類型
   }

   //--- 構建事件資料
   string jsonData = BuildDealJSON(trans, request, eventType);

   //--- 發送到後端
   SendEventToBackend(jsonData);
}

//+------------------------------------------------------------------+
//| 處理 Order 新增事件（掛單）                                          |
//+------------------------------------------------------------------+
void HandleOrderAdd(const MqlTradeTransaction& trans, const MqlTradeRequest& request)
{
   //--- 防止重複處理
   if(trans.order == lastOrderTicket)
      return;

   lastOrderTicket = trans.order;

   //--- 忽略市價單（已由 Deal 處理）
   if(!OrderSelect(trans.order))
      return;

   long orderType = OrderGetInteger(ORDER_TYPE);
   if(orderType == ORDER_TYPE_BUY || orderType == ORDER_TYPE_SELL)
      return;

   //--- 構建事件資料
   string jsonData = BuildOrderJSON(trans, request, "PENDING_ORDER_ADD");

   //--- 發送到後端
   SendEventToBackend(jsonData);
}

//+------------------------------------------------------------------+
//| 處理 Order 修改事件                                                 |
//+------------------------------------------------------------------+
void HandleOrderUpdate(const MqlTradeTransaction& trans, const MqlTradeRequest& request)
{
   //--- 判斷是否為 SL/TP 修改
   if(request.action == TRADE_ACTION_SLTP)
   {
      string jsonData = BuildOrderJSON(trans, request, "SL_TP_MODIFY");
      SendEventToBackend(jsonData);
   }
   else
   {
      string jsonData = BuildOrderJSON(trans, request, "PENDING_ORDER_MODIFY");
      SendEventToBackend(jsonData);
   }
}

//+------------------------------------------------------------------+
//| 處理 Order 刪除事件                                                 |
//+------------------------------------------------------------------+
void HandleOrderDelete(const MqlTradeTransaction& trans, const MqlTradeRequest& request)
{
   string jsonData = BuildOrderJSON(trans, request, "PENDING_ORDER_DELETE");
   SendEventToBackend(jsonData);
}

//+------------------------------------------------------------------+
//| 構建 Deal JSON                                                     |
//+------------------------------------------------------------------+
string BuildDealJSON(const MqlTradeTransaction& trans, const MqlTradeRequest& request, string eventType)
{
   //--- 獲取 Deal 資訊
   double price = HistoryDealGetDouble(trans.deal, DEAL_PRICE);
   double volume = HistoryDealGetDouble(trans.deal, DEAL_VOLUME);
   double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT);
   long magic = HistoryDealGetInteger(trans.deal, DEAL_MAGIC);
   string comment = HistoryDealGetString(trans.deal, DEAL_COMMENT);

   //--- 獲取當前持倉資訊（SL/TP）
   double sl = 0, tp = 0;
   if(PositionSelect(trans.symbol))
   {
      sl = PositionGetDouble(POSITION_SL);
      tp = PositionGetDouble(POSITION_TP);
   }

   //--- 獲取帳戶餘額
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);

   //--- 判斷方向
   string side = "";
   long dealType = HistoryDealGetInteger(trans.deal, DEAL_TYPE);
   if(dealType == DEAL_TYPE_BUY)
      side = "BUY";
   else if(dealType == DEAL_TYPE_SELL)
      side = "SELL";

   //--- 構建 JSON
   string json = "{";
   json += "\"eventType\":\"" + eventType + "\",";
   json += "\"orderId\":" + IntegerToString(trans.order) + ",";
   json += "\"dealId\":" + IntegerToString(trans.deal) + ",";
   json += "\"symbol\":\"" + trans.symbol + "\",";
   json += "\"side\":\"" + side + "\",";
   json += "\"volume\":" + DoubleToString(volume, 2) + ",";
   json += "\"price\":" + DoubleToString(price, _Digits) + ",";
   json += "\"sl\":" + DoubleToString(sl, _Digits) + ",";
   json += "\"tp\":" + DoubleToString(tp, _Digits) + ",";
   json += "\"comment\":\"" + EscapeJSON(comment) + "\",";
   json += "\"magic\":" + IntegerToString(magic) + ",";
   json += "\"profit\":" + DoubleToString(profit, 2) + ",";
   json += "\"balance\":" + DoubleToString(balance, 2) + ",";
   json += "\"timestamp\":" + IntegerToString(TimeCurrent());
   json += "}";

   return json;
}

//+------------------------------------------------------------------+
//| 構建 Order JSON                                                    |
//+------------------------------------------------------------------+
string BuildOrderJSON(const MqlTradeTransaction& trans, const MqlTradeRequest& request, string eventType)
{
   //--- 選擇訂單
   if(!OrderSelect(trans.order))
   {
      // 訂單已刪除,使用 request 資料
      string json = "{";
      json += "\"eventType\":\"" + eventType + "\",";
      json += "\"orderId\":" + IntegerToString(trans.order) + ",";
      json += "\"symbol\":\"" + request.symbol + "\",";
      json += "\"side\":\"" + GetSideFromOrderType(request.type) + "\",";
      json += "\"volume\":" + DoubleToString(request.volume, 2) + ",";
      json += "\"price\":" + DoubleToString(request.price, _Digits) + ",";
      json += "\"sl\":" + DoubleToString(request.sl, _Digits) + ",";
      json += "\"tp\":" + DoubleToString(request.tp, _Digits) + ",";
      json += "\"comment\":\"" + EscapeJSON(request.comment) + "\",";
      json += "\"magic\":" + IntegerToString(request.magic) + ",";
      json += "\"timestamp\":" + IntegerToString(TimeCurrent());
      json += "}";
      return json;
   }

   //--- 獲取訂單資訊
   double price = OrderGetDouble(ORDER_PRICE_OPEN);
   double volume = OrderGetDouble(ORDER_VOLUME_CURRENT);
   double sl = OrderGetDouble(ORDER_SL);
   double tp = OrderGetDouble(ORDER_TP);
   long magic = OrderGetInteger(ORDER_MAGIC);
   string comment = OrderGetString(ORDER_COMMENT);
   long orderType = OrderGetInteger(ORDER_TYPE);

   //--- 構建 JSON
   string json = "{";
   json += "\"eventType\":\"" + eventType + "\",";
   json += "\"orderId\":" + IntegerToString(trans.order) + ",";
   json += "\"symbol\":\"" + trans.symbol + "\",";
   json += "\"side\":\"" + GetSideFromOrderType(orderType) + "\",";
   json += "\"volume\":" + DoubleToString(volume, 2) + ",";
   json += "\"price\":" + DoubleToString(price, _Digits) + ",";
   json += "\"sl\":" + DoubleToString(sl, _Digits) + ",";
   json += "\"tp\":" + DoubleToString(tp, _Digits) + ",";
   json += "\"comment\":\"" + EscapeJSON(comment) + "\",";
   json += "\"magic\":" + IntegerToString(magic) + ",";
   json += "\"timestamp\":" + IntegerToString(TimeCurrent());
   json += "}";

   return json;
}

//+------------------------------------------------------------------+
//| 發送事件到後端（支援重試）                                            |
//+------------------------------------------------------------------+
void SendEventToBackend(string jsonData)
{
   int attempts = 0;
   bool success = false;

   while(attempts < MAX_RETRY && !success)
   {
      attempts++;

      //--- 準備 HTTP 請求
      char postData[];
      StringToCharArray(jsonData, postData, 0, StringLen(jsonData));

      char result[];
      string resultHeaders;

      //--- 設置 Headers
      string headers = "Content-Type: application/json\r\n";
      headers += "Authorization: Bearer " + API_TOKEN + "\r\n";

      //--- 發送請求
      int timeout = 5000; // 5 秒超時
      int response = WebRequest(
         "POST",
         API_URL,
         headers,
         timeout,
         postData,
         result,
         resultHeaders
      );

      //--- 檢查回應
      if(response == 200)
      {
         success = true;
         LogMessage("事件發送成功 (第 " + IntegerToString(attempts) + " 次嘗試)");
      }
      else if(response == 401)
      {
         LogMessage("認證失敗 (401)，請檢查 API_TOKEN");
         break; // 不再重試
      }
      else
      {
         LogMessage("HTTP 錯誤 " + IntegerToString(response) + " (第 " + IntegerToString(attempts) + " 次嘗試)");

         if(attempts < MAX_RETRY)
         {
            Sleep(RETRY_DELAY_MS * attempts); // 指數退避
         }
      }
   }

   //--- 失敗處理
   if(!success)
   {
      LogMessage("所有重試失敗，事件資料: " + jsonData);
   }
}

//+------------------------------------------------------------------+
//| 輔助函數：從訂單類型獲取方向                                          |
//+------------------------------------------------------------------+
string GetSideFromOrderType(long orderType)
{
   switch(orderType)
   {
      case ORDER_TYPE_BUY:
      case ORDER_TYPE_BUY_LIMIT:
      case ORDER_TYPE_BUY_STOP:
      case ORDER_TYPE_BUY_STOP_LIMIT:
         return "BUY";

      case ORDER_TYPE_SELL:
      case ORDER_TYPE_SELL_LIMIT:
      case ORDER_TYPE_SELL_STOP:
      case ORDER_TYPE_SELL_STOP_LIMIT:
         return "SELL";

      default:
         return "UNKNOWN";
   }
}

//+------------------------------------------------------------------+
//| 輔助函數：檢查是否為部分平倉（簡化版）                                 |
//+------------------------------------------------------------------+
bool CheckIfPartialClose(string symbol, double closedVolume)
{
   // 簡化邏輯：如果仍有該商品的持倉，視為部分平倉
   return PositionSelect(symbol);
}

//+------------------------------------------------------------------+
//| 輔助函數：提取主機名                                                 |
//+------------------------------------------------------------------+
string ExtractHostname(string url)
{
   int start = StringFind(url, "://");
   if(start < 0) return "";

   start += 3;
   int end = StringFind(url, "/", start);
   if(end < 0) end = StringLen(url);

   return StringSubstr(url, start, end - start);
}

//+------------------------------------------------------------------+
//| 輔助函數：JSON 字串轉義                                              |
//+------------------------------------------------------------------+
string EscapeJSON(string str)
{
   string result = str;
   StringReplace(result, "\\", "\\\\");
   StringReplace(result, "\"", "\\\"");
   StringReplace(result, "\n", "\\n");
   StringReplace(result, "\r", "\\r");
   StringReplace(result, "\t", "\\t");
   return result;
}

//+------------------------------------------------------------------+
//| 輔助函數：日誌記錄                                                   |
//+------------------------------------------------------------------+
void LogMessage(string message)
{
   if(ENABLE_LOGGING)
   {
      Print("[MT5Notify] ", message);
   }
}
//+------------------------------------------------------------------+
