#property description "監控 MT5 帳戶所有交易事件並推送至 Discord"

//--- 輸入參數
input string    API_URL = "";  // 後端 API URL
input string    API_TOKEN = "";                     // API 認證 Token
input int       MAX_RETRY = 1;                                                   // HTTP 重試次數
input int       RETRY_DELAY_MS = 1;                                          // 重試延遲（毫秒）
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
         // HandleOrderDelete(trans, request); // Removed as per user request
         break;

      case TRADE_TRANSACTION_POSITION:
         HandlePositionUpdate(trans, request);
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
//| 處理 Position 更新事件 (SL/TP 修改)                                  |
//+------------------------------------------------------------------+
void HandlePositionUpdate(const MqlTradeTransaction& trans, const MqlTradeRequest& request)
{
   //--- 確保是有效的持倉
   if(!PositionSelect(trans.symbol))
      return;

   //--- 構建事件資料
   // 這裡我們假設 Position Update 主要是因為 SL/TP 變更 (或其他持倉屬性變更)
   // 為了簡化，我們統一發送 SL_TP_MODIFY 事件，或者可以使用 POSITION_MODIFY
   string jsonData = BuildPositionJSON(trans, request, "SL_TP_MODIFY");

   //--- 發送到後端
   SendEventToBackend(jsonData);
}

//+------------------------------------------------------------------+
//| 構建 Deal JSON                                                     |
//+------------------------------------------------------------------+
string BuildDealJSON(const MqlTradeTransaction& trans, const MqlTradeRequest& request, string eventType)
{
   double price = 0;
   double volume = 0;

   //--- 智慧型重試迴圈：等待有效的價格和數量
   int maxRetries = 25; // 25 次 * 200 毫秒 = 5 秒
   for(int i = 0; i < maxRetries; i++)
   {
      // 每次都嘗試選擇 Deal，確保數據最新
      if(HistoryDealSelect(trans.deal))
      {
         price = HistoryDealGetDouble(trans.deal, DEAL_PRICE);
         volume = HistoryDealGetDouble(trans.deal, DEAL_VOLUME);

         // 如果成功獲取到有效數據，則跳出迴圈
         if(price > 0 && volume > 0)
         {
            break;
         }
      }
      // 等待 200 毫秒後重試
      Sleep(200);
   }

   //--- 最終驗證：如果重試後數據仍然無效，則放棄
   if(price <= 0 || volume <= 0)
   {
      LogMessage("錯誤：在 5 秒後仍無法獲取有效的價格或數量，已跳過此事件。 Deal Ticket: " + IntegerToString(trans.deal));
      return ""; // 返回空字符串，終止後續發送
   }

   //--- 獲取補充資訊 (此時 Deal 肯定已被選中)
   double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT);
   long magic = HistoryDealGetInteger(trans.deal, DEAL_MAGIC);
   string comment = HistoryDealGetString(trans.deal, DEAL_COMMENT);
   long dealType = HistoryDealGetInteger(trans.deal, DEAL_TYPE);

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
   if(dealType == DEAL_TYPE_BUY)
      side = "BUY";
   else if(dealType == DEAL_TYPE_SELL)
      side = "SELL";
   else
      side = "UNKNOWN";

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
   double price = 0;
   double volume = 0;
   double sl = 0;
   double tp = 0;
   long magic = 0;
   string comment = "";
   long orderType = -1;
   string symbol = "";
   string side = "";
   string dataSource = "UNKNOWN";

   //--- 嘗試選擇活躍訂單
   if(OrderSelect(trans.order))
   {
      price = OrderGetDouble(ORDER_PRICE_OPEN);
      volume = OrderGetDouble(ORDER_VOLUME_CURRENT);
      sl = OrderGetDouble(ORDER_SL);
      tp = OrderGetDouble(ORDER_TP);
      magic = OrderGetInteger(ORDER_MAGIC);
      comment = OrderGetString(ORDER_COMMENT);
      orderType = OrderGetInteger(ORDER_TYPE);
      symbol = OrderGetString(ORDER_SYMBOL);
      side = GetSideFromOrderType(orderType);
      dataSource = "ACTIVE_ORDER";
   }
   else
   {
      //--- 嚴格等待模式：循環等待直到歷史數據出現
      // 用戶要求：等到有數據為止，多等幾秒沒關係
      int retryCount = 0;
      int maxRetries = 10; // 10 * 500ms = 5秒
      
      while(retryCount < maxRetries)
      {
         // 載入所有歷史 (確保不漏)
         HistorySelect(0, TimeCurrent() + 3600);

         if(HistoryOrderSelect(trans.order))
         {
            price = HistoryOrderGetDouble(trans.order, ORDER_PRICE_OPEN);
            volume = HistoryOrderGetDouble(trans.order, ORDER_VOLUME_INITIAL);
            sl = HistoryOrderGetDouble(trans.order, ORDER_SL);
            tp = HistoryOrderGetDouble(trans.order, ORDER_TP);
            magic = HistoryOrderGetInteger(trans.order, ORDER_MAGIC);
            comment = HistoryOrderGetString(trans.order, ORDER_COMMENT);
            orderType = HistoryOrderGetInteger(trans.order, ORDER_TYPE);
            symbol = HistoryOrderGetString(trans.order, ORDER_SYMBOL);
            side = GetSideFromOrderType(orderType);
            dataSource = "HISTORY_ORDER";
            
            // 找到數據，跳出迴圈
            break;
         }
         
         // 沒找到，等待 200ms 後重試
         retryCount++;
         if(retryCount < maxRetries)
         {
            Sleep(500);
            if(retryCount % 5 == 0) // 每1秒印一次日誌
            {
               LogMessage("Waiting for history update... Attempt " + IntegerToString(retryCount));
            }
         }
      }

      //--- 如果 5 秒後還是找不到 (極端情況)，最後手段：使用 request 資料
      if(dataSource == "UNKNOWN")
      {
         LogMessage("ERROR: History timeout after 5s. Using fallback data.");
         symbol = request.symbol;
         side = GetSideFromOrderType(request.type);
         volume = request.volume;
         price = request.price;
         sl = request.sl;
         tp = request.tp;
         comment = request.comment;
         magic = (long)request.magic;
         dataSource = "REQUEST_FALLBACK";
      }
   }

   //--- 確保 symbol 不為空 (如果 request 也沒資料)
   if(symbol == "" || symbol == NULL)
   {
      symbol = trans.symbol; 
   }

   //--- 確保 volume 和 price 有值 (如果 request 也沒資料，嘗試從 trans 獲取)
   if(volume <= 0) volume = trans.volume;
   if(price <= 0) price = trans.price;

   //--- 記錄資料來源 (除錯用)
   LogMessage("BuildOrderJSON: Order=" + IntegerToString(trans.order) + ", Source=" + dataSource + ", Vol=" + DoubleToString(volume, 2));

   //--- 構建 JSON
   string json = "{";
   json += "\"eventType\":\"" + eventType + "\",";
   json += "\"orderId\":" + IntegerToString(trans.order) + ",";
   json += "\"symbol\":\"" + symbol + "\",";
   json += "\"side\":\"" + side + "\",";
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
//| 構建 Position JSON                                                 |
//+------------------------------------------------------------------+
string BuildPositionJSON(const MqlTradeTransaction& trans, const MqlTradeRequest& request, string eventType)
{
   //--- 獲取持倉資訊
   long positionId = PositionGetInteger(POSITION_IDENTIFIER);
   double price = PositionGetDouble(POSITION_PRICE_OPEN);
   double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
   double volume = PositionGetDouble(POSITION_VOLUME);
   double sl = PositionGetDouble(POSITION_SL);
   double tp = PositionGetDouble(POSITION_TP);
   double profit = PositionGetDouble(POSITION_PROFIT);
   long magic = PositionGetInteger(POSITION_MAGIC);
   string comment = PositionGetString(POSITION_COMMENT);
   long type = PositionGetInteger(POSITION_TYPE);
   
   string side = (type == POSITION_TYPE_BUY) ? "BUY" : "SELL";

   //--- 構建 JSON
   string json = "{";
   json += "\"eventType\":\"" + eventType + "\",";
   json += "\"orderId\":" + IntegerToString(positionId) + ",";
   json += "\"symbol\":\"" + trans.symbol + "\",";
   json += "\"side\":\"" + side + "\",";
   json += "\"volume\":" + DoubleToString(volume, 2) + ",";
   json += "\"price\":" + DoubleToString(price, _Digits) + ",";
   json += "\"currentPrice\":" + DoubleToString(currentPrice, _Digits) + ",";
   json += "\"sl\":" + DoubleToString(sl, _Digits) + ",";
   json += "\"tp\":" + DoubleToString(tp, _Digits) + ",";
   json += "\"profit\":" + DoubleToString(profit, 2) + ",";
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
   if(StringLen(jsonData) == 0)
   {
      LogMessage("跳過發送事件，因為 JSON 資料為空。");
      return;
   }

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
   switch((int)orderType)
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
