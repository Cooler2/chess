// Константы, типы, глобальные данные и операции над ними
unit gamedata;
interface
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
 movStalemate = 8;   // пат - конец игры
 movRepeat    = $10; // конец игры из-за повторения позиций
 movDB        = $20; // позиция оценена из БД
 movLib       = $40; // ход взят из библиотеки
 movRated     = $80; // узел уже поучаствовал в оценке качества

 movGameOver = movCheckmate+movStalemate+movRepeat; // один из вариантов конца игры

 // Максимальное количество элементов в массиве данных
 {$IFDEF CPUx64}
 memSize = 12000000;
 {$ELSE}
 memSize =  8000000;
 {$ENDIF}

 // Размер кэша оценок
 {$IFDEF CPUx64}
 cacheSize=$1000000; //  16M элементов - 256M памяти
 cacheMask= $FFFFFF;
 {$ELSE}
 cacheSize=$800000; //  8M элементов - 128M памяти
 cacheMask=$7FFFFF;
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
  rFlags:byte;  // флаги рокировки 1,2 - ладьи, 4 - король
  whiteTurn:boolean; // чей сейчас ход
  padding:word;
  // --- поля выше этой строки являются состоянием позиции: участвуют в сравнении и вычислении хэша
  weight:integer;   // используется в библиотеке как вес хода, а в логике - на сколько продлевать лист (1..199)
  depth:byte;
  flags:byte; // флаги последнего хода
  parent,firstChild,lastChild,nextSibling,prevSibling:integer; // ссылки дерева (пустые значения = 0) TODO: возможно prevSibling можно убрать
  whiteRate,blackRate,rate:single; // оценки позиции
  quality:single; // качество оценки - зависит от кол-ва дочерних позиций и глубины просмотра
  lastTurnFrom,lastTurnTo:byte; // параметры последнего хода
  lastPiece:byte; // тип взятой последним ходом фигуры
  debug:byte;
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
 end;

 TMovesList=array[0..63] of byte; // [0] - number of moves, [1]..[n] - target cell position

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

 // Сохранённая в кэше оценка позиции
 TCacheItem=record
  hash:int64;
  rate:single;
  flags:byte; // флаги (рокировки) оцененноё позиции
  quality:byte; // показатель качества оценки
  extra:word; // дополнительное поле, например для обнаружения хэш-коллизий
 end;

 // Сохранённый ход
 TSavedTurn=record
  field:TField;
  whiteTurn:boolean;
  turnFrom,turnTo,weight:byte;
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

 // Кэш оценок позиций: чтобы заново не вычислять оценку позиций, которые уже встречались ранее,
 // т.к. к одной и той же позиции можно прийти по-разному либо на разных стадиях игры.
 // Кэш влияет лишь на скорость оценочной функции, причём незначительно, но чем ближе к эндшпилю - тем сильнее.
 // Однако несовершенство хэш-функции может приводить к ошибкам в оценке.
 cache:array[0..cachesize-1] of TCacheItem;
 cacheMiss,cacheHit:integer;

 // статистика
 spinCounter:int64;

 // Search tree operations
 // ----
 function AllocBoard:integer; inline; // allocate data node
 function AddChild(_parent:integer):integer; // allocate new node and make it child
 procedure DeleteNode(node:integer;updateLinks:boolean=true);
 procedure DeleteChildrenExcept(node,childNode:integer); // удалить всех потомков node, кроме childNode
 function CountLeaves(node:integer):integer;
 procedure VerifyTree; // проверяет целостность дерева: правильность выделения, отсутствие двойных ссылок

 // Операции над доской
 // ---
 // Расставляет фигуры для начала партии а также готовит остальные параметры
 procedure InitNewGame;

 // Сравнение позиций для их сортировки
 function CompareBoards(var b1,b2:TBoard):boolean; overload;
 //function CompareBoards(b1,b2:integer):integer; overload; inline;

 // Вычисление хэша позиции
 function BoardHash(var b:TBoard):int64;

 function GetCachedRate(var b:TBoard;out hash:int64):boolean;
 procedure CacheBoardRate(hash:int64;rate:single);

 // Вспомогательные функции
 // ---
 function NameCell(x,y:integer):string; overload; // формирует имя клетки, например 'b3'
 function NameCell(cell:integer):string; overload; // формирует имя клетки, например 'b3'
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
 uses Apus.MyServis,SysUtils;

 const
  ratesFileName = 'rates.dat';
  libFileName = 'lib.dat';

  // таблица для построение хэша позиций
  randomtab:array[0..511] of cardinal=(
          $5D7ECBC5,$9C063C89,$B94BF27E,$5EF923B6,$10217F1D,$0D1D8B4E,$C750E8EB,$2A4BB3C0,$42FE8E50,$5EFFB9A4,$ED0F8772,$056186F4,$DB53950D,$43938687,$40F00792,$FF3C95CF,
          $1710BA84,$3653F0D5,$A8CC8010,$892D1472,$EE5898EC,$01CAD2D0,$E3711473,$645E1622,$45063500,$951C0DA1,$62243488,$DF48C0C8,$EC24057B,$297C44D1,$F218EBDD,$633B1071,
          $73740AA2,$B7B629D0,$35FA4148,$51DB2ACD,$CAE9F5B8,$BDA55771,$EF67A65F,$329F42B1,$B42C6089,$53BBBD6A,$187176FF,$30530B97,$041A14E2,$927E9BD6,$CD2088C8,$E696BD1B,
          $B4426415,$48070EB4,$04EECA9D,$7F5AA67E,$C46A8E78,$FD832967,$1C48F426,$20695225,$EC093AE5,$4CB4A236,$2E11454F,$A8DC3919,$1BCDFE39,$856F0DCB,$3D2055C9,$BEA30686,
          $CF14F2D7,$A31EAAB7,$2DBFF486,$2C036B3E,$2D746024,$923EBCEA,$8F2D1740,$8D118135,$FC35720A,$C5E0793D,$351BD9F1,$4D3ABF05,$5FD40078,$1D2980EB,$A1308E59,$F4BD7B69,
          $6D8066DE,$18D4ED11,$3C87DB7D,$C62D00C4,$8C9F6BB4,$60ADEA33,$612DED25,$ABF1309A,$A84837F2,$9916E3B8,$33A6B35B,$75C5B713,$30C85E97,$88843F6B,$4C6831F1,$6639CE7D,
          $ED20F424,$8D00A8FB,$315CDFF9,$103092C9,$9C83B620,$61A8ED7A,$9F62174C,$8460E50B,$67DA4294,$342E66DF,$A3CB9406,$CED6DEFC,$23415F8E,$0A56F786,$85DF0407,$C471D67A,
          $5F8A52A0,$777A95AC,$8057A672,$2064F104,$4BB74860,$A20866F6,$4AE2FB2F,$F1B74741,$6682CBE8,$99016BE9,$73A2826B,$58C49878,$FFD74E55,$F979BB72,$88AE8C15,$94BC8E17,
          $8A57BE4A,$E41B4E5D,$11901760,$61228F2E,$BCD52F6C,$42A45AE0,$58C6C245,$A34C23F3,$83DA91E5,$5D65400F,$0543C901,$67E8E93E,$C32279E4,$C0C40167,$83ED1591,$3072140C,
          $E71EF71A,$72BA5246,$411F5F3B,$90C184FF,$46737C3C,$7854316F,$B2265A07,$1C796BDA,$5378D685,$AB351489,$2EC6F63F,$A4987B07,$9DBA3533,$DF10A39E,$9AB4AFF5,$C4ECAB13,
          $A3794108,$5730049E,$DF1BEE7B,$C1998E2E,$732A43C8,$8BF1B6DC,$341A73EB,$B49633AD,$1CF55FBF,$4046FE8E,$3A42DC9F,$0B2E9B8A,$F436D73A,$E734E04F,$E41B2EB8,$5381B9E1,
          $A0FE640C,$5953AC9E,$2F9E7999,$5A030A73,$01919F09,$DA521B5E,$AFB9856A,$96FAB425,$DBE8778B,$6E72F756,$E5D09298,$EC013C80,$5F2FBAF2,$800859B1,$6B392951,$B18ACB31,
          $7546AC1E,$D4FD757D,$EABEF90B,$1456FD88,$E442AAF5,$D44FF32E,$EA1DC7FC,$C2FD49FA,$3FEBEBE2,$1B90DC1A,$638972A1,$EB6AF3A1,$AB3D3F51,$646415FD,$2F27FB3A,$885D8DB9,
          $69E9E936,$BA056E74,$3C94A94A,$FEEA0F22,$41D38885,$FEC13684,$9C5C391A,$0BF775E3,$AC940EBA,$C1786E12,$59821B34,$01C0FAA4,$D8F8C751,$63217F6A,$22FDC3EA,$5554D431,
          $7C7F6F4C,$8C448ABB,$C5380ACF,$7C178AFC,$74DE5CB2,$F27F4197,$738F9A3A,$1941DC99,$397CB60C,$6E035275,$E1D66EC8,$7B5B2F41,$1CF8B9E8,$5F166431,$2DD366D9,$69C79552,
          $92F47E93,$08D05481,$908BA800,$A6173B5E,$3E07FAF1,$693312AB,$3205782F,$647C3E50,$490DBB04,$DFE22325,$2D354F9F,$78B2F5E3,$511849A8,$82A8D068,$49F8B720,$B63B4931,
          $B530CB7C,$78250912,$14DDDF03,$46331B38,$4FCE9E65,$154DF363,$C0AA069D,$ACC6665D,$0061090A,$4AE610BF,$D7D6F3CA,$1EB6E7E6,$04CBFA57,$630CF131,$BE0E7A66,$26D85B7D,
          $22E3D8FD,$0EAE76E4,$01B213D3,$9B9546B2,$A1F262EE,$C310A9A9,$7D578678,$E46C5478,$14389CE3,$67491A76,$49459D3E,$8F6C40A5,$F067D1D8,$51C5D6E4,$7CF8EF14,$36BD5374,
          $FB25A28C,$95C2ECAE,$C0A1B66A,$B6166D04,$808D2504,$A0D57D37,$AEA5B8B7,$B046A0D8,$5DAC1407,$28646102,$051A3DF5,$64AD6157,$DA060EA1,$672B5B39,$A74F1822,$D4C23B4B,
          $5110E7A2,$AABADD29,$6F43BABF,$398D2165,$ABB5051F,$30F359C3,$CF2B6252,$C92C47B5,$A9D4CFEE,$558E291A,$42EF4BE6,$CC518F34,$FBBE332B,$0F97FBE9,$91ABFC88,$03C0813D,
          $2BBA2BB8,$BEEDDF0D,$DF3198C9,$5DD3DB0D,$578367B7,$49C3CF05,$8D834C41,$FBF7A949,$B9C7F610,$8A20DB77,$EE5BC109,$882EF376,$03A805EF,$0B60DAAC,$C4A4A73E,$DA8DF780,
          $863DB644,$17B3AD11,$96004C82,$EEBEF535,$2C0FF544,$159B10B6,$CC43437C,$297E89C9,$429E6FE5,$357104D0,$A6F51B56,$EE1E9B53,$13DC9164,$6EDFBD39,$FCD2273C,$8404D44C,
          $4FAF92C0,$CE6425ED,$CD4B55E1,$4C28AF15,$45719A3E,$12D5F68D,$A20418FB,$46991170,$ED71EAE5,$9AD955DE,$C0565CC4,$E7F87803,$C2712401,$A26A0D49,$2ACD8F7A,$3EFAB1DA,
          $6B2890A3,$D0594C5B,$72A9B8DE,$69E92BE4,$33C0871D,$13C9FC44,$595EA1B7,$5C21CC73,$5758D888,$D1B0A359,$42160B4D,$F3955EBF,$19815040,$625BD894,$732CF6F0,$5E498E62,
          $AFC24364,$DEE94710,$27B1FD71,$CFD772DB,$FB163059,$3ECD4190,$70E9B6A6,$86EDAB0D,$116A6E46,$C54FE5F8,$E7CD30E9,$22CC08BF,$9722EC98,$BF09D0D0,$2E887897,$48C8CC1B,
          $E893027D,$8F6C60C7,$41FC2F92,$99CC6F31,$13894E6A,$0E3B8A2B,$9B3D34C1,$F7D50174,$A0C1A598,$350D3A74,$21125B8E,$1B75133A,$2D6D1380,$1CCD4BB8,$E9793365,$7950313E,
          $D4B5E965,$4B3B0836,$CB22DF39,$77A0F01F,$6932DDC9,$506A3DCD,$BEF1FD01,$F3B287E0,$7E733BF4,$B442E184,$117E9D35,$1768FF68,$427A2372,$33FE4302,$64974A54,$7EB7E802,
          $273ED794,$4FADD015,$80BB205F,$AD29A8DD,$5C291EEC,$27B3682D,$F69EF45C,$D35B5A8A,$1799B2D3,$AA473FE0,$90AA8BD6,$E47E3283,$B061BEE5,$10F45467,$9479E45A,$FBD77EA0,
          $87477082,$AE1A6F1D,$D45E8AFA,$124130A2,$C085964D,$0A6DB904,$90DC03CC,$03A8F9AA,$CD4B4FAE,$5273DE42,$2A2C4169,$E48EF5C0,$C539CC51,$1408C19E,$A1B92C71,$A788E750,
          $8FE71BA7,$4BDBC006,$EBA53B03,$12BF02A6,$DE600C62,$C2F0840A,$10431847,$05724977,$F4A01BFB,$BC1E6960,$1D9C5BE7,$0D70765A,$431B762E,$F1917060,$E8ED518F,$4CA17849,
          $D038047B,$E247C187,$A026D073,$AE7C7E22,$71D08DA5,$6F95C0F6,$2B6B22C7,$6D90922A,$D6B2E534,$CAA1B1F2,$5E94FD46,$E8FDC587,$60202AF4,$B1E7EA64,$FAAE86AE,$C9FAEBC3,
          $5E9F1658,$6391A189,$98C1E210,$423660CC,$0BF95072,$5C61D4A0,$10CE70D6,$663246D3,$B23B3BD0,$C308127C,$8A9C93D5,$F8941332,$DFD48210,$4F1BF689,$2AC18B7F,$EB0CEBD4
          );

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
    depth:=data[_parent].depth+1;
    weight:=data[_parent].weight-10;
    rFlags:=data[_parent].rFlags;
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
   d:integer;
  begin
   // 1. Удаление всех потомков
   d:=data[node].firstChild;
   while d>0 do begin
    _DeleteNode(d,true);
    d:=data[d].nextSibling;
   end;
   FreeBoard(node);

   if updateLinks then with data[node] do begin
    if prevSibling>0 then data[prevSibling].nextSibling:=nextSibling;
    if nextSibling>0 then data[nextSibling].prevSibling:=prevSibling;
    if (parent>0) then begin
     if data[parent].firstChild=node then data[parent].firstChild:=nextSibling;
     if data[parent].lastChild=node then data[parent].lastChild:=prevSibling;
    end;
   end;
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
   next:integer;
  begin
   node:=data[node].firstChild;
   while (node>0) do begin
    next:=data[node].nextSibling;
    if node<>childNode then DeleteNode(node);
    node:=next;
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


 procedure VerifyTree; // проверяет целостность дерева: правильность выделения, отсутствие двойных ссылок
  var
   i,n:integer;
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
   for i:=1 to high(freeList)-1 do begin
    n:=freeList[i];
    if (i<freeCnt) and (data[n].debug<>0) then
     raise EError.Create('Free node was allocated');
   end;

   n:=CountNodes(1);
   if n+freeCnt+1<>memSize then
    raise EError.Create('Tree node count doesn''t match');

   MarkSubtree(1,data[1].parent);

   for i:=1 to high(data) do begin
    if data[i].debug<>0 then inc(data[i].debug);
    ASSERT(data[i].debug in [0,$DD]);
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

{ function CompareBoards(b1,b2:integer):integer;
  begin
   result:=CompareBoards(data[b1],data[b2]);
  end;}

 function CompareBoards(var b1,b2:TBoard):boolean;
  begin
   result:=CompareMem(@b1,@b2,sizeof(TField)+2);
  end;

 const
  BOARD_DATA_SIZE = sizeof(TField)+2;

 // Важно, чтобы хэш получался одинаковый и в 32 и в 64-битном режиме.
 // В x64 можно было бы сделать быстрее, но тогде в x86 совместимая реализация будет гораздо медленнее.
 // Сейчас компромиссный вариант: работает с одинаковой скоростью, хоть и не так быстро
 function BoardHash(var b:TBoard):int64;
  {$IFDEF CPU386}
  asm
   push esi
   push edi
   push ebx
   mov esi,b
   mov ecx,BOARD_DATA_SIZE
   xor eax,eax
   xor edx,edx
   xor ebx,ebx
   xor edi,edi
@01:
   add dl,[esi]
   add bl,[esi]
   xor eax,[offset randomtab+edx*4]
   xor edi,[offset randomtab+ebx*4+1024]
   sub dl,ah
   add bl,al
   inc esi
   dec ecx
   jnz @01
   mov edx,edi
   pop ebx
   pop edi
   pop esi
  end;
  {$ELSE}
  asm
   push rsi
   push rdi
   push rbx
   mov rsi,b
   mov rcx,BOARD_DATA_SIZE
   xor rax,rax
   xor rdx,rdx
   xor rbx,rbx
   xor rdi,rdi
   mov r8,offset randomtab
@01:
   add dl,[rsi]
   add bl,[rsi]

   xor eax,[r8+rdx*4]
   xor rdi,[r8+rbx*4+1024]
//   xor rax,[r8+rdx*8]
//   xor rdi,[r8+rbx*8]
   sub dl,ah
   add bl,al
   inc rsi
   dec rcx
   jnz @01
//   xor rax,rdi
   shl rdi,32
   or rax,rdi
   pop rbx
   pop rdi
   pop rsi
  end;
  {$ENDIF}

 function GetCachedRate(var b:TBoard;out hash:int64):boolean;
  var
   h:integer;
  begin
   hash:=BoardHash(b);
   h:=hash and CacheMask;
   if cache[h].hash=hash then
    with b do begin
     inc(cacheHit);
     whiterate:=1;
     blackrate:=1;
     rate:=cache[h].rate; // точность оценки 0.001
     if cache[h].flags and 1>0 then flags:=flags or movDB; // TODO: восстанавливать все необходимые флаги
     if PlayerWhite then rate:=-rate;
     result:=true;
    end
   else
    result:=false;
  end;

 procedure CacheBoardRate(hash:int64;rate:single);
  var
   h:integer;
  begin
   h:=hash and CacheMask;
   cache[h].hash:=hash;
   cache[h].rate:=round(rate*1000) shl 8;
   inc(cacheMiss);
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
   plrs:array[boolean] of string=('white','black');
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
      writeln(f,Format('%s;from=%d;to=%d;plr=%s;weight=%d',
       [FieldToStr(field),turnFrom,turnTo,plrs[whiteTurn],weight]));
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
     SaveLibrary;
     exit;
    end;
   // не найдено
   SetLength(turnLib,n+1);
   turnlib[n].field:=data[board].cells;
   turnlib[n].turnFrom:=p1;
   turnlib[n].turnTo:=p2;
   turnlib[n].weight:=weight;
  end;

 /// TODO: дублируется код - переписать
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
   b:TBoard;
  begin
    for i:=0 to high(dbRates) do begin
     move(dbRates[i],b,sizeof(TField)+2);
     hash:=BoardHash(b);
     h:=hash and cacheMask;
     cache[h].hash:=hash;
     cache[h].rate:=dbRates[i].rate;
     cache[h].flags:=dbRates[i].rFlags or movDB;
     cache[h].quality:=dbRates[i].quality;
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
   //cells[y]:=(cells[y] and not ($F shl x)) or (value shl x);
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

{ TSavedTurn }

function TSavedTurn.CompareWithBoard(var b: TBoard): boolean;
 begin
  result:=false;
  if (b.lastTurnFrom<>turnFrom) or (b.lastTurnTo<>turnTo)
    or (b.whiteTurn<>whiteTurn) then exit;
  if CompareMem(@b.cells,@field,sizeof(field)) then exit;
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

end.
