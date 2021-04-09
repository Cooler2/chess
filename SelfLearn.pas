{ База данных оценок.
  -------------------
  В отличие от кэша, база оценок предназначена для хранения/применения оценок позиций с высоким качеством.
  Оценки, вычисленные в ходе одной партии, могут быть использованы в будущем.
  ---
  Есть два сценария использования оценок: более простой и более сложный:

  1. Оценка влияет только на оценку дерева, но не влияет на развитие дерева.
     Позиция получает качество=1 и развивается так же, как и любая другая.
     Если качество позиции превысило качество оценки БД, то позиция становится обычной
     и её оценка заменяется на вычисленную рекурсивно.
     Минусы: тратятся ресурсы на развитие таких позиций.
     Плюсы: простота, развитие все-равно может понадобиться при уточнении оценки
       или переходе к следующему ходу.

  2. Оценка влияет на развитие дерева.
     Позиция получает качество из БД и поэтому не выбирается для развития.
     Когда же всё-таки наступит необходимость её развить, необходимо преобразовать
     её в обычную:
     - понизить качество до 1 (и отразить это в предках)
     - выполнить развитие до необходимого уровня (требует много времени)
     Плюсы: не тратится время и память на развитие веток дерева (которые, возможно,
       вообще будут обрезаны)
     Минусы: если развитие игры пойдёт по тупи такой ветки, её так или иначе придётся
       развивать, что потребует дополнительных ресурсов. Однако, раз позиция была в базе,
       вероятно её продолжения также там найдутся, что сократит время развития дерева.
 }
unit SelfLearn;
interface
 uses gamedata;

const
 ratesFileName = 'rates.dat';

type
 // Запись БД оценок
 TRateEntry=record
  // информация о позиции - точно такая как в TBoard
  cells:TField;
  rFlags:byte;
  whiteTurn:boolean;
  // ---
  playerIsWhite:boolean;
  rate:single;
  quality:integer;
  procedure FromString(st:string);
  function ToString:string;
 end;

var
 // база оценок
 dbRates:array of TRateEntry;

 procedure LoadRates; // Загрузка из файла
 procedure SaveRates; // Сохранение в файл
 procedure UpdateCacheWithRates; // заносит оценки из базы в кэш, чтобы EstimatePosition() их применяла
 procedure UpdateRatesBase; // заносит в базу оценки из текущего состояния дерева (и сохраняет в файл)

implementation
 uses Apus.MyServis,SysUtils,cache;

 function GetRatesFromNode(node:integer):boolean;
  function UpdateRateForBoard:boolean;
   var
    i,q:integer;
    rate:single;
   begin
    result:=false;
    i:=0;
    while i<=high(dbRates) do begin
     if CompareMem(@dbRates[i],@data[node],sizeof(TField)+2) then break;
     inc(i);
    end;
    q:=round(data[node].quality);
    rate:=data[node].rate;
    if i>high(dbRates) then begin
     // Добавить новую запись
     result:=true;
     SetLength(dbRates,i+1);
     dbRates[i].cells:=data[node].cells;
     dbRates[i].rFlags:=data[node].rFlags;
     dbRates[i].whiteTurn:=data[node].whiteTurn;
     dbRates[i].playerIsWhite:=playerWhite;
     dbRates[i].rate:=rate;
     dbRates[i].quality:=q;
    end else begin
     // Обновить существующую
     if q<=dbRates[i].quality then exit;
     result:=true;
     dbRates[i].rate:=rate;
     dbRates[i].quality:=q;
    end;
   end;
  begin
   result:=false;
   if data[node].quality>1000 then begin
    if UpdateRateForBoard then result:=true;
    node:=data[node].firstChild;
    while node>0 do begin
     if GetRatesFromNode(node) then result:=true;
     node:=data[node].nextSibling;
    end;
   end;
  end;

 procedure UpdateRatesBase; // сохраняет в базу оценки из текущего состояния дерева
  begin
   if (curboard.depth<2) or (curBoard.depth>30) then exit; // столь ранние и поздние оценки не нужны, чтобы не засорять базу
   if curBoard.quality<1000 then exit;
   if GetRatesFromNode(curBoardIdx) then SaveRates;
  end;

 // Оценки из базы хранятся в кэше вместе с другими кэшированными оценками
 procedure UpdateCacheWithRates;
  var
   i,h:integer;
   hash:int64;
   b:TBoard;
   rate:single;
   q:integer;
  begin
    for i:=0 to high(dbRates) do begin
     move(dbRates[i],b,sizeof(TField)+2);
     BoardHash(b,hash);
     h:=hash and cacheMask;
     rateCache[h].hash:=hash;
     rateCache[h].cells:=b.cells;
     rate:=dbRates[i].rate;
     if playerWhite=dbRates[i].playerIsWhite then rate:=-rate; // оценка за другого игрока
     rateCache[h].rate:=rate;
     rateCache[h].flags:=dbRates[i].rFlags or movDB;
     rateCache[h].quality:=Clamp(dbRates[i].quality,0,65500);
    end;
  end;

 // Загрузка базы данных оценок
 procedure LoadRates;
  var
   f:TextFile;
   n:integer;
   st:string;
  begin
   if not fileExists(ratesFileName) then exit;
   try
    assign(f,ratesFileName);
    reset(f);
    while not eof(f) do begin
     readln(f,st);
     n:=length(dbRates);
     SetLength(dbRates,n+1);
     dbRates[n].FromString(st);
    end;
    close(f);
   except
    on e:exception do ErrorMessage('Error in LoadDB: '+e.message);
   end;
  end;

 procedure SaveRates;
  var
   f:TextFile;
   i:integer;
  begin
   try
    assign(f,ratesFileName);
    rewrite(f);
    for i:=0 to high(dbRates) do
     writeln(f,dbRates[i].ToString);
    close(f);
   except
    on e:exception do ErrorMessage('Error in SaveDB: '+e.message);
   end;
  end;

{ TRateEntry }

 procedure TRateEntry.FromString(st: string);
  var
   i:integer;
   sa:StringArr;
   pair:TNameValue;
  begin
   sa:=Split(';',st);
   for i:=0 to high(sa) do begin
    pair.Init(sa[i]);
    if pair.Named('cells') then cells:=FieldFromStr(pair.value) else
    if pair.Named('white') then whiteTurn:=pair.GetInt<>0 else
    if pair.Named('plrW') then playerIsWhite:=pair.GetInt<>0 else
    if pair.Named('rF') then rFlags:=pair.GetInt else
    if pair.Named('r') then rate:=pair.GetFloat else
    if pair.Named('q') then quality:=pair.GetInt;
   end;
 end;

 function TRateEntry.ToString: string;
  begin
   result:=Format('cells=%s; white=%d; plrW=%d; rF=%d; r=%.3f; q=%d',
    [FieldToStr(cells),byte(whiteTurn),byte(playerWhite),rFlags,rate,quality]);
  end;

end.
