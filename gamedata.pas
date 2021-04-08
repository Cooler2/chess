// Константы, типы, глобальные данные и операции над ними
unit gamedata;
interface
uses Apus.MyServis;
const
 Pawn   = 1;
 Rook   = 2;
 Knight = 3;
 Bishop = 4;
 Queen  = 5;
 King   = 6;

 {$IFDEF COMPACT}
 White  = 0;
 Black  = 8;
 {$ELSE}
 White  = $40;
 Black  = $80;
 {$ENDIF}

 PawnWhite   = Pawn+White;
 RookWhite   = Rook+White;
 KnightWhite = Knight+White;
 BishopWhite = Bishop+White;
 QueenWhite  = Queen+White;
 KingWhite   = King+White;

 PawnBlack   = Pawn+Black;
 RookBlack   = Rook+Black;
 KnightBlack = Knight+Black;
 BishopBlack = Bishop+Black;
 QueenBlack  = Queen+Black;
 KingBlack   = King+Black;

 ColorMask = Black+White;
 PieceMask = 7;

 // Флаги для TBoard.flags
 movBeat      = 1;   // ход со взятием фигуры
 movCheck     = 2;   // ход с шахом
 movCheckmate = 4;   // мат - конец игры
 movStalemate = 8;   // пат либо ничья - конец игры
 movRepeat    = $10; // конец игры из-за повторения позиций
 movDB        = $20; // позиция оценена из БД
 movLib       = $40; // ход взят из библиотеки
 movRated     = $80; // узел уже поучаствовал в оценке качества

 movGameOver = movCheckmate+movStalemate+movRepeat; // один из вариантов конца игры

 // Максимальное количество элементов в массиве данных.
 {$IFDEF CPUx64}
 memSize = 12000000;
 {$ELSE}
 memSize =  8000000;
 {$ENDIF}

type
 {$IFDEF COMPACT}
 TField=array[0..7] of cardinal; // индекс - у-координата (т.е. хранение построчное)
 {$ELSE}
 TField=array[0..7,0..7] of byte; // [x,y] - хранение по столбцам
 {$ENDIF}
 PField=^TField;

 PBoard=^TBoard;
 TBoard=record
  cells:TField; // [x,y]
  rFlags:byte;  // флаги рокировки 1,2 - ладьи, 4 - король, 8 - уже сделана ($10/$20/$40/$80 - для черных)
  whiteTurn:boolean; // чей сейчас ход
  padding:word;
  // --- поля выше этой строки являются состоянием позиции: участвуют в сравнении и вычислении хэша
  weight:integer;   // используется в библиотеке как вес хода, а в логике - на сколько продлевать лист (1..199)
  depth:byte;
  flags:byte; // флаги последнего хода
  wKingPos,bKingPos:byte; // позиции королей на доске
  parent,firstChild,lastChild,nextSibling,prevSibling:integer; // ссылки дерева (пустые значения = 0) TODO: возможно prevSibling можно убрать
  whiteRate,blackRate,rate:single; // оценки позиции
  quality:single; // качество оценки - зависит от кол-ва дочерних позиций и глубины просмотра
  lastTurnFrom,lastTurnTo:byte; // параметры последнего хода
  lastPiece:byte; // тип взятой последним ходом фигуры
  debug:byte;
  {$IFDEF CHECK_HASH}
  hash:int64;
  {$ENDIF}
  procedure Clear;
  function CellIsEmpty(x,y:integer):boolean; inline;
  function CellOccupied(x,y:integer):boolean; inline;
  function GetCell(x,y:integer):byte; inline;
  procedure SetCell(x,y:integer;value:integer); {$IFNDEF COMPACT} inline; {$ENDIF}
  function GetPieceType(x,y:integer):byte; inline;
  function GetPieceColor(x,y:integer):byte; inline;
  function HasChild(turnFrom,turnTo:integer):integer; // есть ли среди потомков вариант с указанным ходом? Если есть - возвращает его
  procedure FromString(st:string);
  function ToString:string;
  function LastTurnAsString(short:boolean=true):string;
  procedure UpdateKings;
  procedure MinMaxRate(out min,max:single);
 end;

 TMovesList=array[0..35] of byte; // [0] - number of moves, [1]..[n] - target cell position

 // Запись БД оценок
 TRateEntry=record
  // информация о позиции - точно такая как в TBoard
  cells:TField;
  rFlags:byte;
  whiteTurn:boolean;
  // ---
  rate:single;
  quality:byte;
  procedure FromString(st:string);
  function ToString:string;
 end;

 // Сохранённый ход
 TSavedTurn=record
  field:TField; // позиция на моментначала хода
  whiteTurn:boolean; // чей был ход
  turnFrom,turnTo,weight:byte; // откуда и куда ход, вес - приоритет для выбора
  function CompareWithBoard(var b:TBoard):boolean;
 end;

 // устанавливаются флаги Black/White для полей, находящихся под боем
 // биты: 0-2 - тип младшей белой фигуры, способной взять это поле
 //       3-5 - тип младшей черной фигуры, способной взять это поле
 //       6 - поле под боем у белой фигуры
 //       7 - поле под боем у черной фигуры
 TBeatable=array[0..7,0..7] of byte;

var
 // Память: здесь хранится всё дерево поиска и история партии (ствол)
 data:array of TBoard; // [0] - служебный фейковый элемент, в дереве не используется
 freeList:array of integer; // список свободных эл-тов
 freeCnt:NativeInt; // кол-во свободных элементов в списке
 dataLocker:NativeInt; // блокировка дерева (а также связанных с ним структур)
 totalLeafCount:NativeInt; // общее количество листьев в дереве поиска
 globalLock:TMyCriticalSection;

 // Текущее состояние игры
 gameState:byte; // 0 - игра, 1 - пат, 2 - мат белым, 3 - мат черным, 4 - пауза
 // Текущая позиция
 curBoardIdx:integer; // индекс текущей позиции в дереве
 curBoard:PBoard; // указатель для удобства

 playerWhite:boolean=true; // за кого играет человек
 gameStage:integer; // 1 - дебют, 2 - миттельшпиль, 3 - эндшпиль

 // библиотека
 turnLib:array of TSavedTurn;

 // база оценок
 dbRates:array of TRateEntry;

 // статистика
 spinCounter:int64;
 testNode:integer; // для ассертов

 // Search tree operations
 // ----
 function AllocBoard:integer; inline; // allocate data node
 function AddChild(_parent:integer):integer; // allocate new node and make it child
 procedure DeleteNode(node:integer;updateLinks:boolean=true);
 procedure DeleteChildrenExcept(node,childNode:integer); // удалить всех потомков node, кроме childNode
 function CountLeaves(node:integer):integer; // считает количество всех листьев у ноды
 function CountNodes(node:integer):integer; // возвращает 1+кол-во всех потомков
 procedure VerifyTree; // проверяет целостность дерева: правильность выделения, отсутствие двойных ссылок

 // Операции над доской
 // ---
 // Расставляет фигуры для начала партии а также готовит остальные параметры
 procedure InitNewGame;

 // Сравнение позиций для их сортировки
 function CompareBoards(var b1,b2:TBoard):boolean; overload;
 //function CompareBoards(b1,b2:integer):integer; overload; inline;

 // Вспомогательные функции
 // ---
 function NameCell(x,y:integer):string; overload; // формирует имя клетки, например 'b3'
 function NameCell(cell:integer):string; overload; // формирует имя клетки, например 'b3'
 function BuildLine(node:integer):string; // формирует цепочку ходов от текущей позиции к указанной
 function FieldToStr(f:TField):string;
 function FieldFromStr(st:string):TField;
 function IsPlayerTurn:boolean; // true - ход игрока, false - противника

 procedure SpinLock(var lock:NativeInt); inline;
 procedure Unlock(var lock:NativeInt); inline;

 // Библиотека: база "книжных" ходов
 // ---
 procedure LoadLibrary;
 procedure SaveLibrary;
 procedure AddLastMoveToLibrary(weight:byte);
 procedure AddAllMovesToLibrary(weight:byte);
 procedure DeleteLastMoveFromLibrary;

 // База оценок позиций
 procedure LoadRates;
 procedure SaveRates;
 procedure UpdateCacheWithRates;

implementation
 uses SysUtils,cache;

 const
  ratesFileName = 'rates.dat';
  libFileName = 'lib.dat';

 procedure SpinLock(var lock:NativeInt); inline;
  begin
   while AtomicCmpExchange(lock,1,0)<>0 do begin
    inc(spinCounter);
    YieldProcessor;
   end;
   MemoryBarrier; /// TODO: возможно не всегда нужен
  end;

 procedure Unlock(var lock:NativeInt); inline;
  begin
   MemoryBarrier;
   lock:=0;
  end;

 function AllocBoard:integer;
  begin
   if freeCnt=0 then exit(0);
   dec(freeCnt);
   result:=freeList[freeCnt];
   data[result].firstChild:=0;
   data[result].lastChild:=0;
   ASSERT(data[result].debug=0);
   data[result].debug:=$DD; // allocated
  end;

 procedure FreeBoard(index:integer); inline;
  begin
   ASSERT(data[index].debug=$DD,'Index='+inttostr(index));
   data[index].debug:=0;
   data[index].parent:=-1;
   data[index].firstChild:=-1;
   freeList[freecnt]:=index;
   inc(freecnt);
  end;

 function AddChild(_parent:integer):integer;
  begin
   SpinLock(dataLocker);
   result:=AllocBoard;
   if result=0 then begin
    Unlock(dataLocker);
    exit;
   end;
   with data[result] do begin
    parent:=_parent;
    nextSibling:=0; prevSibling:=data[_parent].lastChild;
    cells:=data[_parent].cells;
    rFlags:=data[_parent].rFlags;
    wKingPos:=data[parent].wKingPos;
    bKingPos:=data[parent].bKingPos;
    depth:=data[_parent].depth+1;
    weight:=data[_parent].weight-10;
    whiteTurn:=not data[_parent].whiteTurn;

    flags:=0;
    quality:=1;
   end;
   with data[_parent] do begin
    if (lastChild>0) then begin
     // не первый потомок
     data[lastChild].nextSibling:=result;
     lastChild:=result;
    end else begin
     // первый потомок
     lastChild:=result;
     firstChild:=result;
    end;
   end;
   Unlock(dataLocker);
  end;

 // Удаление узла из дерева
 procedure _DeleteNode(node:integer;updateLinks:boolean=true);
  var
   d,next:integer;
  begin
   // 1. Удаление всех потомков
   d:=data[node].firstChild;
   while d>0 do begin
    next:=data[d].nextSibling;
    _DeleteNode(d,true);
    d:=next;
   end;
   if updateLinks then with data[node] do begin
    if prevSibling>0 then data[prevSibling].nextSibling:=nextSibling;
    if nextSibling>0 then data[nextSibling].prevSibling:=prevSibling;
    if (parent>0) then begin
     if data[parent].firstChild=node then data[parent].firstChild:=nextSibling;
     if data[parent].lastChild=node then data[parent].lastChild:=prevSibling;
    end;
   end;
   FreeBoard(node);
  end;

 // Удаление узла из дерева
 procedure DeleteNode(node:integer;updateLinks:boolean=true);
  begin
   SpinLock(dataLocker);
   _DeleteNode(node,updateLinks);
   Unlock(dataLocker);
  end;

 procedure DeleteChildrenExcept(node,childNode:integer);
  var
   orig,next:integer;
  begin
   orig:=node;
   node:=data[node].firstChild;
   while (node>0) do begin
    next:=data[node].nextSibling;
    if node<>childNode then DeleteNode(node);
    node:=next;
   end;
   with data[orig] do
   if firstChild>0 then begin
    ASSERT(firstChild=childNode);
    ASSERT(lastChild=childNode);
    ASSERT(data[childNode].prevSibling=0);
    ASSERT(data[childNode].nextSibling=0);
   end else begin
    ASSERT(firstChild=0);
    ASSERT(lastChild=0);
   end;
  end;

 function CountLeaves(node:integer):integer;
  var
   d:integer;
  begin
   result:=0;
   d:=data[node].firstChild;
   if d=0 then exit(1);
   while d>0 do begin
    inc(result,CountLeaves(d));
    d:=data[d].nextSibling;
   end;
  end;

 function CountNodes(node:integer):integer;
  var
   d:integer;
  begin
   result:=1;
   d:=data[node].firstChild;
   if d=0 then exit;
   while d>0 do begin
    inc(result,CountNodes(d));
    d:=data[d].nextSibling;
   end;
  end;

 // Проверяет целостность дерева: правильность выделения, отсутствие двойных ссылок
 // Вызывать только при остановленных потоках AI
 procedure VerifyTree;
  var
   i,n,p,d:integer;
  procedure MarkSubtree(node,parent:integer);
   begin
    ASSERT(data[node].debug=$DD);
    ASSERT(data[node].parent=parent);
    dec(data[node].debug);
    parent:=node;
    node:=data[node].firstChild;
    while node>0 do begin
     MarkSubtree(node,parent);
     node:=data[node].nextSibling;
    end;
   end;
  begin
   // проверка ствола дерева
   n:=curBoardIdx;
   i:=curBoard.depth;
   p:=n;
   while n>1 do begin
    testNode:=n;
    ASSERT(data[n].nextSibling=0);
    p:=n;
    n:=data[n].parent;
    ASSERT(data[n].depth=i-1);
    dec(i);
    ASSERT(data[n].firstChild=p);
    ASSERT(data[n].lastChild=p);
   end;

   d:=curBoard.depth;
   // Проверка иерархии
   for i:=2 to high(data) do
    if data[i].debug<>0 then
     with data[i] do begin
      testNode:=i;
      ASSERT(parent>0);
      ASSERT(data[parent].depth=depth-1);
{      if depth>d+1 then
       ASSERT(data[parent].weight>=weight);}
      if depth<d then begin
       // ствол дерева
       ASSERT(nextSibling=0);
       ASSERT(prevSibling=0);
       ASSERT(firstChild>0);
       ASSERT(data[firstChild].parent=i);
       ASSERT(data[firstChild].depth=depth+1);
       ASSERT(lastChild=firstChild);
      end;
     end;

   for i:=1 to high(freeList)-1 do begin
    n:=freeList[i];
    if (i<freeCnt) and (data[n].debug<>0) then begin
     testNode:=n;
     raise EError.Create('Free node was allocated');
    end;
   end;

   n:=CountNodes(1);
  // if n+freeCnt+1<>memSize then // либо дерево содержит освобождённые ноды, либо есть ноды вне дерева
  //  raise EError.Create('Tree node count doesn''t match');

   MarkSubtree(1,data[1].parent);

   for i:=1 to high(data) do begin
    testNode:=i;
    if data[i].debug<>0 then inc(data[i].debug);
    if not (data[i].debug in [0,$DD]) then
     ASSERT(false,inttostr(i)); // debug=$DE - нода вне дерева, $DC - дважды в дереве
   end;
  end;

 procedure InitNewGame;
  var
   i:integer;
  begin
   LogMessage('Init New Game');
   // Init data storage
   SetLength(data,memSize);
   ZeroMem(data[0],length(data)*sizeof(TBoard));
   SetLength(freeList,memSize);
   freecnt:=0;
   // список свободных элементов. [0] - не используется
   for i:=memsize-1 downto 1 do begin
    freeList[freecnt]:=i;
    inc(freecnt);
   end;
   curBoardIdx:=AllocBoard;
   curBoard:=@data[curBoardIdx];

   // Начальная позиция
   with curBoard^ do begin
    Clear;
    for i:=0 to 7 do begin
     SetCell(i,1,PawnWhite);
     SetCell(i,6,PawnBlack);
    end;
    SetCell(0,0,RookWhite);
    SetCell(1,0,KnightWhite);
    SetCell(2,0,BishopWhite);
    SetCell(3,0,QueenWhite);
    SetCell(4,0,KingWhite);
    SetCell(5,0,BishopWhite);
    SetCell(6,0,KnightWhite);
    SetCell(7,0,RookWhite);

    SetCell(0,7,RookBlack);
    SetCell(1,7,KnightBlack);
    SetCell(2,7,BishopBlack);
    SetCell(3,7,QueenBlack);
    SetCell(4,7,KingBlack);
    SetCell(5,7,BishopBlack);
    SetCell(6,7,KnightBlack);
    SetCell(7,7,RookBlack);

    whiteTurn:=true;
    whiteRate:=0;
    blackRate:=0;
    parent:=-1;
    rFlags:=0;
   end;
   gameState:=0;
  end;

 function NameCell(x,y:integer):string;
  begin
   result:=chr(97+x)+inttostr(y+1);
  end;

 function NameCell(cell:integer):string;
  begin
   result:=NameCell(cell and $F,cell shr 4);
  end;

 function BuildLine(node:integer):string;
  begin
   while node>0 do
    with data[node] do begin
     result:=NameCell(lastTurnFrom)+'-'+NameCell(lastTurnTo)+' / '+result;
     node:=parent;
     if node=curBoardIdx then exit;
    end;
   result:='[no path]';
  end;

{ function CompareBoards(b1,b2:integer):integer;
  begin
   result:=CompareBoards(data[b1],data[b2]);
  end;}

 function CompareBoards(var b1,b2:TBoard):boolean;
  begin
   result:=CompareMem(@b1,@b2,sizeof(TField)+2);
  end;

 procedure LoadLibrary;
  var
   f:text;
   st:string;
   sa:StringArr;
   nv:TNameValue;
   i,n:integer;
  begin
   if fileexists(libFileName) then begin
    try
     LogMessage('Loading turns library');
     assign(f,libFileName);
     reset(f);
     while not eof(f) do begin
      readln(f,st);
      sa:=Split(';',st);
      n:=length(turnLib);
      SetLength(turnLib,n+1);

      for i:=0 to high(sa) do begin
       nv.Init(sa[i],'=');
       if nv.value='' then turnLib[n].field:=FieldFromStr(nv.name)
       else
       if nv.Named('from') then turnLib[n].turnFrom:=nv.GetInt
       else
       if nv.Named('to') then turnLib[n].turnTo:=nv.GetInt
       else
       if nv.Named('weight') then turnLib[n].weight:=nv.GetInt
       else
       if nv.Named('plr') then turnLib[n].whiteTurn:=SameText(nv.value,'white');
      end;
     end;
     close(f);
     LogMessage('Library loaded: %d records',[n]);
    except
     on e:Exception do begin
      ErrorMessage('Ошибка доступа к файлу. Возможно диск защищен от записи.');
      halt;
     end;
    end;
   end;
  end;

 procedure SaveLibrary;
  const
   colorIsWhite:array[boolean] of string=('black','white');
  var
   i,n:integer;
   f:text;
  begin
   LogMessage('Saving library');
   try
    assign(f,libFileName);
    rewrite(f);
    for i:=0 to high(turnLib) do
     with turnLib[i] do
      writeln(f,Format('%s;from=%d;to=%d;plr=%s;weight=%d;desc=%s',
       [FieldToStr(field),turnFrom,turnTo,colorIsWhite[whiteTurn],weight,NameCell(turnFrom)+'-'+NameCell(turnTo)]));
    close(f);
   except
    on e:Exception do begin
     ForceLogMessage('Save error: '+ExceptionMsg(e));
     ErrorMessage('Ошибка сохранения библиотеки: '#13#10+ExceptionMsg(e));
    end;
   end;
  end;

 // Добавляет ход в библиотеку (без сохранения её на диск)
 procedure AddMoveToLibrary(board:integer;weight:byte);
  var
   i,n:integer;
   f:file;
   p1,p2:byte;
  begin
   // Проверить, есть ли уже такой ход в библиотеке
   n:=length(turnLib);
   p1:=data[board].lastTurnFrom;
   p2:=data[board].lastTurnTo;
   for i:=0 to n-1 do
    if turnLib[i].CompareWithBoard(data[board]) then begin
     turnlib[i].weight:=weight; // update weight
     exit;
    end;
   // не найдено
   SetLength(turnLib,n+1);
   turnlib[n].turnFrom:=p1;
   turnlib[n].turnTo:=p2;
   turnlib[n].weight:=weight;
   // фактическая позиция перед ходом - в предке
   board:=data[board].parent;
   ASSERT(board>0);
   turnlib[n].field:=data[board].cells;
   turnLib[n].whiteTurn:=data[board].whiteTurn;
  end;

 procedure AddLastMoveToLibrary(weight:byte);
  begin
   if curBoard.parent<0 then exit;
   AddMoveToLibrary(curBoardIdx,weight);
   SaveLibrary;
  end;

 procedure AddAllMovesToLibrary(weight:byte);
  var
   idx:integer;
  begin
   idx:=curBoardIdx;
   while data[idx].parent>=0 do begin
    AddMoveToLibrary(idx,weight);
    idx:=data[idx].parent;
   end;
   SaveLibrary;
  end;

 procedure DeleteLastMoveFromLibrary;
  var
   i,n,b:integer;
  begin
   b:=curBoard.parent;
   if b<0 then exit;
   n:=length(turnLib);
   for i:=0 to n-1 do
    if turnLib[i].CompareWithBoard(data[b]) then begin
     n:=i;
     while n<high(turnLib) do begin
      turnlib[n]:=turnlib[n+1];
      inc(n);
     end;
     SetLength(turnlib,n);
     SaveLibrary;
     exit;
    end;
  end;

 // Оценки из базы хранятся в кэше вместе с другими кэшированными оценками
 procedure UpdateCacheWithRates;
  var
   i,h:integer;
   hash:int64;
   extHash:int64;
   b:TBoard;
  begin
    for i:=0 to high(dbRates) do begin
     move(dbRates[i],b,sizeof(TField)+2);
     BoardHash(b,hash);
     h:=hash and cacheMask;
     rateCache[h].hash:=hash;
     rateCache[h].cells:=b.cells;
     rateCache[h].rate:=dbRates[i].rate;
     rateCache[h].flags:=dbRates[i].rFlags or movDB;
     rateCache[h].quality:=dbRates[i].quality;
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
    UpdateCacheWithRates;
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

 function IsPlayerTurn:boolean;
  begin
   result:=not curBoard.whiteTurn xor playerWhite;
  end;

{ TBoard }

 function TBoard.CellIsEmpty(x,y:integer):boolean;
  begin
   {$IFDEF COMPACT}
   result:=cells[y] and ($F shl (x*4))=0;
   {$ELSE}
   result:=cells[x,y]=0;
   {$ENDIF}
  end;

 function TBoard.CellOccupied(x,y:integer):boolean;
  begin
   {$IFDEF COMPACT}
   result:=cells[y] and ($F shl (x*4))<>0;
   {$ELSE}
   result:=cells[x,y]<>0;
   {$ENDIF}
  end;

 procedure TBoard.Clear;
  begin
   fillchar(cells,sizeof(cells),0);
  end;

function FieldFromStr(st: string):TField;
  var
   i,p,v:integer;
   c:char;
   b:TBoard;
  begin
   p:=0;
   b.Clear;
   for i:=1 to length(st) do begin
    c:=st[i];
    case c of
     '.':v:=0;
     'a':v:=PawnWhite;
     'b':v:=RookWhite;
     'c':v:=KnightWhite;
     'd':v:=BishopWhite;
     'e':v:=QueenWhite;
     'f':v:=KingWhite;
     'A':v:=PawnBlack;
     'B':v:=RookBlack;
     'C':v:=KnightBlack;
     'D':v:=BishopBlack;
     'E':v:=QueenBlack;
     'F':v:=KingBlack;
     else continue;
    end;
    b.SetCell(p mod 8,p div 8,v);
    inc(p);
   end;
   result:=b.cells;
  end;

 function GetPieceType(const f:TField;x,y:integer):integer; inline;
  begin
   {$IFDEF COMPACT}
   result:=(f[y] shr (x*4)) and PieceMask;
   {$ELSE}
   result:=f[x,y] and PieceMask;
   {$ENDIF}
  end;

 function GetPieceColor(const f:TField;x,y:integer):integer; inline;
  begin
   {$IFDEF COMPACT}
   result:=(f[y] shr (x*4)) and ColorMask;
   {$ELSE}
   result:=f[x,y] and ColorMask;
   {$ENDIF}
  end;

 function FieldToStr(f:TField):string;
  var
   x,y,piece:integer;
   c:char;
   b:TBoard;
  begin
   b.cells:=f;
   SetLength(result,64);
   for y:=0 to 7 do
    for x:=0 to 7 do begin
     piece:=GetPieceType(f,x,y);
     if piece>0 then
      c:=Char(ord('a')+piece-1)
     else
      c:='.';
     if GetPieceColor(f,x,y)=Black then c:=UpCase(c);
     result[1+x+y*8]:=c;
    end;
  end;

 function TBoard.GetCell(x,y:integer):byte;
  begin
   {$IFDEF COMPACT}
   result:=(cells[y] shr (x*4)) and $F;
   {$ELSE}
   result:=cells[x,y];
   {$ENDIF}
  end;

 function TBoard.GetPieceColor(x,y:integer):byte;
  begin
   {$IFDEF COMPACT}
   result:=(cells[y] shr (x*4)) and ColorMask;
   {$ELSE}
   result:=cells[x,y] and ColorMask;
   {$ENDIF}
  end;

 function TBoard.GetPieceType(x,y:integer):byte;
  begin
   {$IFDEF COMPACT}
   result:=(cells[y] shr (x*4)) and PieceMask;
   {$ELSE}
   result:=cells[x,y] and PieceMask;
   {$ENDIF}
  end;

 procedure TBoard.SetCell(x,y:integer;value:integer);
  {$IFDEF COMPACT}
  asm
   // rcx - self
   // rdx - x
   // r8 - y
   // r9 - value
   lea r10,[rcx+r8*4] // адрес строки данных, rcx свободен
   mov rcx,rdx // rdx свободен
   shl rcx,2 // rcx = x*4
   mov eax,[r10] // строка данных
   mov rdx,15
   shl rdx,cl // rdx - маска
   not rdx
   and eax,edx
   shl r9,cl // r9 = value shl x*4
   or eax,r9d
   mov [r10],eax // сохраняем результат
  end;
 {$ELSE}
  begin
   cells[x,y]:=value;
  end;
 {$ENDIF}

 function TBoard.ToString: string;
  begin
   result:=Format('cells=%s; white=%d; from=%d; to=%d; rF=%d; f=%d',
    [FieldToStr(cells),byte(whiteTurn),lastTurnFrom,lastTurnTo,rFlags,flags]);
  end;

 procedure TBoard.UpdateKings;
  var
   i,j,v:integer;
  begin
   for i:=0 to 7 do
    for j:=0 to 7 do begin
     v:=GetCell(i,j);
     if v=KingWhite then wKingPos:=i+j shl 4
     else
     if v=KingBlack then bKingPos:=i+j shl 4;
    end;
  end;

procedure TBoard.FromString(st: string);
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
    if pair.Named('from') then lastTurnFrom:=pair.GetInt else
    if pair.Named('to') then lastTurnTo:=pair.GetInt else
    if pair.Named('rF') then rFlags:=pair.GetInt else
    if pair.Named('f') then flags:=pair.GetInt;
   end;
   UpdateKings;
  end;

 function TBoard.HasChild(turnFrom,turnTo:integer):integer;
  begin
   result:=firstChild;
   while result>0 do
    with data[result] do begin
     if (lastTurnFrom=turnFrom) and (lastTurnTo=turnTo) then exit;
     result:=nextSibling;
    end;
  end;


function TBoard.LastTurnAsString;
 var
  x,y,v:integer;
  st:string;
 begin
  x:=lastTurnTo and $F;
  y:=lastTurnTo shr 4;
  v:=GetPieceType(x,y);
  if not short then
   case v of
    Knight:st:='К';
    Queen:st:='Ф';
    Rook:st:='Л';
    Bishop:st:='С';
    King:st:='Кр';
    Pawn:st:=' ';
   end;
  st:=st+NameCell(lastTurnFrom);
  if lastPiece<>0 then st:=st+':' else st:=st+'-';
  st:=st+NameCell(lastTurnTo);
  if (v=King) and (x=LastTurnFrom and $F-2) then st:='0-0-0';
  if (v=King) and (x=LastTurnFrom and $F+2) then st:='0-0';
  result:=st;
 end;

procedure TBoard.MinMaxRate(out min, max: single);
 var
  d:integer;
 begin
  min:=10000; max:=-10000;
  d:=firstChild;
  while d>0 do
   with data[d] do begin
    if rate<min then min:=rate;
    if rate>max then max:=rate;
    d:=nextSibling;
   end;
 end;

{ TSavedTurn }

function TSavedTurn.CompareWithBoard(var b: TBoard): boolean;
 begin
  result:=false;
  if (b.lastTurnFrom<>turnFrom) or (b.lastTurnTo<>turnTo)
    or (not b.whiteTurn<>whiteTurn) then exit;
  if b.parent<=0 then exit;
  if not CompareMem(@data[b.parent].cells,@field,sizeof(field)) then exit;
  result:=true;
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
    if pair.Named('rF') then rFlags:=pair.GetInt else
    if pair.Named('r') then rate:=pair.GetFloat else
    if pair.Named('q') then quality:=pair.GetInt;
   end;
 end;

 function TRateEntry.ToString: string;
  begin
   result:=Format('cells=%s; white=%d; rF=%d; r=%.3f; q=%d',
    [FieldToStr(cells),byte(whiteTurn),rFlags,rate,quality]);
  end;

initialization
 InitCritSect(globalLock,'global');
finalization
 DeleteCritSect(globalLock);
end.
