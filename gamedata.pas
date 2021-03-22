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

 PawnWhite=Pawn+White;
 RookWhite=Rook+White;
 KnightWhite=Knight+White;
 BishopWhite=Bishop+White;
 QueenWhite=Queen+White;
 KingWhite=King+White;

 PawnBlack=Pawn+Black;
 RookBlack=Rook+Black;
 KnightBlack=Knight+Black;
 BishopBlack=Bishop+Black;
 QueenBlack=Queen+Black;
 KingBlack=King+Black;

 ColorMask=Black+White;

 // Флаги для TBoard.flags
 movBeat=1; // ход со взятием фигуры
 movCheck=2; // ход с шахом
 movRepeat=$10; // проигрыш из-за повторения позиций
 movDB=$20; // позиция оценена из БД


 memsize=2500000;
 cachesize=$400000;
 cacheMask=$3FFFFF;

type
 {$IFDEF COMPACT}
 TField=array[0..7] of cardinal;
 {$ELSE}
 TField=array[0..7,0..7] of byte;
 {$ENDIF}
 PField=^TField;

 TBoard=record
  field:TField; // [x,y]
  rFlags:byte; // флаги рокировки 1,2 - ладьи, 4 - король
  WhiteTurn:boolean;
  weight:shortint; // используется в библиотеке как вес хода, а в логике - на сколько продлевать лист
  depth:shortint;
  whiteRate,blackRate,rate:single;
  lastTurnFrom,lastTurnTo,lastPiece:byte; // параметры посл. хода
  flags:byte; // флаги последнего хода
  parent,firstChild,lastChild,next,prev:integer; // ссылки дерева
  procedure Clear;
  function CellEmpty(x,y:integer):boolean; inline;
  function GetCell(x,y:integer):byte; inline;
  procedure SetCell(x,y:integer;value:byte); inline;
  function GetPieceType(x,y:integer):byte; inline;
  function GetPieceColor(x,y:integer):byte; inline;
 end;

 TMovesList=array[0..199] of byte; // [0] - number of moves, [1]..[n] - target cell position

 TCacheItem=record
  hash:int64;
  rate:integer;
 end;

var
 gameover:byte; // 0 - игра, 1 - пат, 2 - мат белым, 3 - мат черным, 4 - пауза
 // Текущая позиция
 board:TBoard;
 selected:array[0..7,0..7] of byte;
 playerWhite:boolean=true; // за кого играет человек
 animation:integer=0;
 gamestage:integer; // 1 - дебют, 2 - миттельшпиль, 3 - эндшпиль

 // история партии
 history:array[1..300] of TBoard;
 historyPos,historySize:integer;

 // библиотека
 turnLib:array of TBoard;

 // база оценок
 dbItems:array of TCacheItem;

 // устанавливаются флаги Black/White для полей, находящихся под боем
 // биты: 0-2 - тип младшей белой фигуры
 //       3-5 - тип младшей черной фигуры
 //       6 - под боем у белой фигуры
 //       7 - под боем у черной фигуры
 beatable:array[0..7,0..7] of byte;

 // Память
 data:array[1..memsize] of TBoard;
 freeList:array[1..memsize] of integer; // список свободных эл-тов
 freecnt:integer; // кол-во свободных эл-тов в списке
 leafs:integer;

 // Очередь
 qu:array[1..memsize] of integer;
 qstart,qlast:integer;

 // кэш оценок позиций
 cache:array[0..cachesize-1] of TCacheItem;
 cacheMiss,cacheUse:integer;

 estCounter:integer;

 // Search tree operations
 // ----
 function AddChild(root:integer):integer;
 procedure DeleteNode(node:integer;updateLinks:boolean=true);
 function CountLeaves(node:integer):integer;

 // Операции над доской
 // ---
 // Расставляет фигуры для начала партии а также готовит остальные параметры
 procedure InitBoard(var board:TBoard);
 // Сравнение позиций для их сортировки
 function CompareBoards(var b1,b2:TBoard):integer;
 // Вычисление хэша позиции
 function BoardHash(var b:TBoard):int64;

 // Вспомогательные функции
 // ---
 function NameCell(x,y:integer):string; // формирует имя клетки, например 'b3'

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

 function AddChild(root:integer):integer;
  begin
   result:=freeList[freecnt];
   dec(freecnt);
   with data[result] do begin
    parent:=root;
    next:=0; prev:=0;
    firstChild:=0;
    lastChild:=0;
    flags:=0;
   end;
   with data[root] do begin
    if (lastChild>0) then begin
     // не первый потомок
     data[lastChild].next:=result;
     data[result].prev:=lastChild;
     lastChild:=result;
    end else begin
     // первый потомок
     lastChild:=result;
     firstChild:=result;
    end;
   end;
  end;

 // Удаление узла из дерева
 procedure DeleteNode(node:integer;updateLinks:boolean=true);
  var
   d:integer;
  begin
   // 1. Удаление всех потомков
   d:=data[node].firstChild;
   while d>0 do begin
    DeleteNode(d,false);
    d:=data[d].next;
   end;
   inc(freecnt);
   freeList[freecnt]:=node;
   if updateLinks then with data[node] do begin
    if prev>0 then data[prev].next:=next;
    if next>0 then data[next].prev:=prev;
    if (parent>0) then begin
     if data[parent].firstChild=node then data[parent].firstChild:=next;
     if data[parent].lastChild=node then data[parent].lastChild:=prev;
    end;
   end;
  end;


 function CountLeaves(node:integer):integer;
  var
   d:integer;
  begin
   result:=0;
   d:=data[node].firstChild;
   if d=0 then begin
    result:=1; exit;
   end;
   while d>0 do begin
    inc(result,CountLeaves(d));
    d:=data[d].next;
   end;
  end;

 procedure InitBoard(var board:TBoard);
  var
   i:integer;
  begin
   board.Clear;
   with board do begin
    for i:=0 to 7 do begin
     SetCell(i,1,PawnWhite);
     SetCell(i,6,PawnBlack);
    end;
    field[0,0]:=$42; field[0,7]:=$82;
    field[1,0]:=$43; field[1,7]:=$83;
    field[2,0]:=$44; field[2,7]:=$84;
    field[3,0]:=$45; field[3,7]:=$85;
    field[4,0]:=$46; field[4,7]:=$86;
    field[5,0]:=$44; field[5,7]:=$84;
    field[6,0]:=$43; field[6,7]:=$83;
    field[7,0]:=$42; field[7,7]:=$82;
    whiteTurn:=true;
    whiteRate:=0;
    blackRate:=0;
    parent:=0;
    rFlags:=0;
   end;
   historyPos:=0; // нет предыдущих состояний
   gameover:=0;
  end;

 function NameCell(x,y:integer):string;
  begin
   result:=chr(97+x)+inttostr(y+1);
  end;

 function CompareBoards(var b1,b2:TBoard):integer;
  asm
   push esi
   push edi
   mov esi,b1
   mov edi,b2
   mov ecx,66
@01:
   mov dl,[esi]
   cmp dl,[edi]
   ja @above
   jb @below
   inc esi
   inc edi
   dec ecx
   jnz @01
   xor eax,eax
   pop edi
   pop esi
   pop ebp
   ret 8
@above:
   mov eax,1
   pop edi
   pop esi
   pop ebp
   ret 8
@below:
   mov eax,-1
   pop edi
   pop esi
   pop ebp
   ret 8
  end;


 function BoardHash(var b:TBoard):int64;
  asm
   push esi
   push edi
   push ebx
   mov esi,b
   mov ecx,66
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

 procedure LoadLibrary;
  var
   f:file;
   i,j,n:integer;
   t:text;
   v:cardinal;
   fl:boolean;
  begin
   if fileexists(libFileName) then begin
    try
     assign(f,libFileName);
     filemode:=0;
     reset(f,1);
     n:=filesize(f) div 128;
     setLength(turnLib,n);
     for i:=0 to n-1 do begin
      seek(f,i*128);
      blockread(f,turnlib[i],sizeof(TBoard));
     end;
     close(f);
    except
     on e:Exception do begin
      ErrorMessage('Ошибка доступа к файлу. Возможно диск защищен от записи.');
      halt;
     end;
    end;
   end;
   filemode:=2;
   fl:=false;
   i:=2;
   n:=length(turnlib);
   while i<n do begin
    for j:=1 to i-1 do
     if (CompareBoards(turnlib[i],turnlib[j])=0) and
        (turnlib[i].lastTurnFrom=turnlib[j].lastTurnFrom) and
        (turnlib[i].lastTurnTo=turnlib[j].lastTurnTo) then begin
      turnlib[i]:=turnlib[n-1];
      dec(n);
      dec(i);
     end;
    inc(i);
   end;
   if n<length(turnlib) then begin
    setLength(turnlib,n);
    SaveLibrary;
   end;
  end;

 procedure SaveLibrary;
  var
   i,n:integer;
   f:file;
  begin
   assign(f,libFileName);
   rewrite(f,1);
   n:=length(turnLib);
   for i:=0 to n-1 do begin
    seek(f,i*128);
    blockwrite(f,turnlib[i],sizeof(TBoard));
   end;
   close(f);
  end;

 procedure AddLastMoveToLibrary(weight:byte);
  var
   i,n:integer;
   f:file;
   p1,p2:byte;
  begin
   if historyPos=0 then exit;
   // Проверить, есть ли уже такой ход в библиотеке
   n:=length(turnLib);
   p1:=board.lastTurnFrom;
   p2:=board.lastTurnTo;
   for i:=0 to n-1 do
    if (CompareBoards(turnLib[i],history[historypos])=0) and
       (turnlib[i].lastTurnFrom=p1) and (turnlib[i].lastTurnTo=p2) then begin
     turnlib[i].weight:=weight;
     SaveLibrary;
     exit;
    end;
   // не найдено
   setLength(turnLib,n+1);
   turnlib[n]:=history[historypos];
   turnlib[n].lastTurnFrom:=p1;
   turnlib[n].lastTurnTo:=p2;
   turnlib[n].weight:=weight;
   SaveLibrary;
  end;

 procedure AddAllMovesToLibrary(weight:byte);
  var
   i,n,j:integer;
   f:file;
   p1,p2:byte;
   addflag:boolean;
  begin
   if historyPos=0 then exit;
   for j:=1 to historyPos do begin
    // Проверить, есть ли уже такой ход в библиотеке
    if j=historyPos then begin
     p1:=board.lastTurnFrom;
     p2:=board.lastTurnTo;
    end else begin
     p1:=history[j+1].lastTurnFrom;
     p2:=history[j+1].lastTurnTo;
    end;
    n:=length(turnLib);
    addflag:=true;
    for i:=0 to n-1 do
     if (CompareBoards(turnLib[i],history[j])=0) and
        (turnlib[i].lastTurnFrom=p1) and (turnlib[i].lastTurnTo=p2) then begin
      turnlib[i].weight:=weight;
      addflag:=false;
      break;
     end;
    if addflag then begin
     // не найдено
     setLength(turnLib,n+1);
     turnlib[n]:=history[j];
     turnlib[n].lastTurnFrom:=p1;
     turnlib[n].lastTurnTo:=p2;
     turnlib[n].weight:=weight;
    end;
   end;
   SaveLibrary;
  end;


 procedure DeleteLastMoveFromLibrary;
  var
   i,n:integer;
  begin
   if historypos=0 then exit;
   n:=length(turnLib);
   for i:=0 to n-1 do
    if CompareBoards(turnLib[i],history[historypos])=0 then begin
     turnlib[i]:=turnlib[n-1];
     SetLength(turnlib,n-1);
     SaveLibrary;
     exit;
    end;
  end;


 procedure LoadRates;
  var
   f:file;
   i,n,h:integer;
  begin
   if not fileExists(ratesFileName) then exit;
   try
    assign(f,ratesFileName);
    reset(f,1);
    n:=filesize(f) div 12;
    setLength(dbItems,n);
    blockread(f,dbItems[0],n*12);
    close(f);
    for i:=0 to n-1 do begin
     h:=dbItems[i].hash and cacheMask;
     cache[h]:=dbItems[i];
     cache[h].rate:=cache[h].rate or 1;
    end;

   except
    on e:exception do ErrorMessage('Error in LoadDB: '+e.message);
   end;
  end;

 procedure SaveRates;
  var
   f:file;
  begin
   try
    assign(f,ratesFileName);
    rewrite(f,1);
    blockwrite(f,dbItems[0],12*length(dbItems));
    close(f);
   except
    on e:exception do ErrorMessage('Error in SaveDB: '+e.message);
   end;
  end;

{ TBoard }

function TBoard.CellEmpty(x,y:integer):boolean;
 begin
  result:=field[x,y]=0;
 end;

procedure TBoard.Clear;
 begin
  fillchar(field,sizeof(field),0);
 end;

function TBoard.GetCell(x,y:integer):byte;
 begin
  result:=field[x,y];
 end;

function TBoard.GetPieceColor(x,y:integer):byte;
 begin
  result:=field[x,y] and ColorMask;
 end;

function TBoard.GetPieceType(x,y:integer):byte;
 begin
  result:=field[x,y] and 7;
 end;

procedure TBoard.SetCell(x,y:integer;value:byte);
 begin
  field[x,y]:=value;
 end;

end.
