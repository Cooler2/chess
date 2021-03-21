{$A4}
unit logic;
interface
 uses classes;

const
 White=$40;
 Black=$80;

 Pawn=$1;
 Rook=$2;
 Knight=$3;
 Bishop=$4;
 Queen=$5;
 King=$6;

 PawnWhite=$41;
 RookWhite=$42;
 KnightWhite=$43;
 BishopWhite=$44;
 QueenWhite=$45;
 KingWhite=$46;

 PawnBlack=$81;
 RookBlack=$82;
 KnightBlack=$83;
 BishopBlack=$84;
 QueenBlack=$85;
 KingBlack=$86;

 ColorMask=$C0;

 // флаги
 amValid=1; // только корректные ходы

 movBeat=1; // ход со взятием фигуры
 movCheck=2; // ход с шахом
 movRepeat=$10; // проигрыш из-за повторения позиций
 movDB=$20; // позиция оценена из БД

 // штраф за незащищенную фигуру под боем
 bweight:array[0..6] of single=(0,1, 5.2, 3.1, 3.1, 9.3, 1000);
 bweight2:array[0..6] of single=(0,1, 3.1, 3.1, 5.2, 9.3, 1000);

type
 TField=array[0..63] of byte;
 PField=^TField;
 TBoard=record
  field:array[0..7,0..7] of byte; // [x,y]
  rFlags:byte; // флаги рокировки 1,2 - ладьи, 4 - король
  WhiteTurn:boolean;
  weight:shortint; // используется в библиотеке как вес хода, а в логике - на сколько продлевать лист
  depth:shortint;
  WhiteRate,BlackRate,rate:single;
  lastTurnFrom,lastTurnTo,lastPiece:byte; // параметры посл. хода
  flags:byte; // флаги последнего хода
  parent,firstChild,lastChild,next,prev:integer; // ссылки дерева
 end;

 TCacheItem=record
  hash:int64;
//  rate:single;
  rate:integer;
 end;

 ThinkThread=class(TThread)
  moveFrom,moveTo:byte;
  moveReady:boolean;
  status:string;
  useLibrary,advSearch,selfTeach,running:boolean;
  level,plimit,d1,d2:byte;
  procedure Reset;
  procedure Execute; override;
  function ThinkIteration(root:integer;iteration:byte):boolean;
  procedure DoThink;
 end;

const
 memsize=2500000;
 cachesize=$400000;
 cacheMask=$3FFFFF;
var
 gameover:byte; // 0 - игра, 1 - пат, 2 - мат белым, 3 - мат черным, 4 - пауза
 // Текущая позиция
 board:TBoard;
 selected:array[0..7,0..7] of byte;
 PlayerWhite:boolean=true; // за кого играет человек
 thread:ThinkThread;
 animation:integer=0;
 gamestage:integer; // 1 - дебют, 2 - миттельшпиль, 3 - эндшпиль

 // история партии
 history:array[1..300] of TBoard;
 historyPos,historySize:integer;

 // библиотека
 turnLib:array of TBoard;

 // база оценок
 dbItems:array of TCacheItem;

 // Результат генератора ходов
 moves:array[1..200] of byte;
 mCount:integer;

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

 procedure InitBoard(var board:TBoard);

 // Составляет список возможных ходов для данной фигуры (в массив moves)
 procedure GetAvailMoves(var board:TBoard;piece:byte);

 // отмечает поля, находящиеся под боем
 procedure CalcBeatable(var board:TBoard);

 procedure DoMove(var board:TBoard;from,target:byte);

 // библиотека
 procedure AddLastMoveToLibrary(weight:byte);
 procedure AddAllMovesToLibrary(weight:byte);
 procedure DeleteLastMoveFromLibrary;

 // оценка позиции (rate - за черных)
 procedure EstimatePosition(var b:TBoard;quality:byte;noCache:boolean=false);
 function NameCell(x,y:integer):string;

 function CompareBoards(var b1,b2:TBoard):integer; stdcall;
 function BoardHash(var b:TBoard):int64; stdcall;

 // загрузка и сохранение базы оценок
 procedure LoadDB;
 procedure SaveDB;

implementation
 uses windows,sysUtils,Apus.MyServis;

 const
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


 function NameCell(x,y:integer):string;
  begin
  result:=chr(97+x)+inttostr(y+1);
  end;


 function CompareBoards(var b1,b2:TBoard):integer; stdcall;
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


 function BoardHash(var b:TBoard):int64; stdcall;
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

 procedure CalcBeatable2(var board:TBoard);
  var
   i,j,k,n,x,y:integer;
   fig,figpos:array[1..32] of byte;
  begin
   fillchar(beatable,sizeof(beatable),0);
   with board do begin
    n:=0;
    for x:=0 to 7 do
     for y:=0 to 7 do
      if field[x,y]>0 then begin
       inc(n);
       figpos[n]:=x+y shl 4;
       case field[x,y] of
        PawnWhite:fig[n]:=1;
        KnightWhite:fig[n]:=2;
        BishopWhite:fig[n]:=3;
        RookWhite:fig[n]:=4;
        QueenWhite:fig[n]:=5;
        KingWhite:fig[n]:=6;
        PawnBlack:fig[n]:=1+Black;
        KnightBlack:fig[n]:=2+Black;
        BishopBlack:fig[n]:=3+Black;
        RookBlack:fig[n]:=4+Black;
        QueenBlack:fig[n]:=5+Black;
        KingBlack:fig[n]:=6+Black;
       end;
      end;
    for i:=1 to n do
     if fig[i] and $F=6 then begin
//      if
     end;
   end;
  end;

 procedure CalcBeatable(var board:TBoard);
{  const
   fig:array[0..63] of byte=
    (0,1,2,1,3,1,2,1,4,1,2,1,3,1,2,1,5,1,2,1,3,1,2,1,4,1,2,1,3,1,2,1,6,1,2,1,3,1,2,1,4,1,2,1,3,1,2,1,5,1,2,1,3,1,2,1,4,1,2,1,3,1,2,1);}
  var
   x,y,i:integer;
   v,whitecnt,blackcnt:byte;
   bit:integer;
  begin
   with board do
   for y:=0 to 7 do
    for x:=0 to 7 do begin
     v:=0;
     beatable[x,y]:=0;
     whitecnt:=0; blackcnt:=0;
     bit:=0;
     // определить под боем ли поле x,y
     // пешки
     if (y>1) and (x>0) and (field[x-1,y-1]=PawnWhite) then bit:=1;
     if (y>1) and (x<7) and (field[x+1,y-1]=PawnWhite) then bit:=1;

     if bit=0 then begin // кони
      if (x>1) and (y>0) and (field[x-2,y-1]=KnightWhite) then bit:=2;
      if (x>1) and (y<7) and (field[x-2,y+1]=KnightWhite) then bit:=2;
      if (x<6) and (y>0) and (field[x+2,y-1]=KnightWhite) then bit:=2;
      if (x<6) and (y<7) and (field[x+2,y+1]=KnightWhite) then bit:=2;
      if (x>0) and (y>1) and (field[x-1,y-2]=KnightWhite) then bit:=2;
      if (x<7) and (y>1) and (field[x+1,y-2]=KnightWhite) then bit:=2;
      if (x>0) and (y<6) and (field[x-1,y+2]=KnightWhite) then bit:=2;
      if (x<7) and (y<6) and (field[x+1,y+2]=KnightWhite) then bit:=2;
     end;
     if bit=0 then begin
      for i:=1 to 7 do begin // вправо-вверх
       if (x+i>7) or (y+i>7) then break;
       case field[x+i,y+i] of
        BishopWhite:bit:=bit or 4;
        QueenWhite:bit:=bit or 16;
        KingWhite:if i=1 then bit:=bit or 32;
       end;
       if field[x+i,y+i]<>0 then break;
      end;
      for i:=1 to 7 do begin // вправо-вниз
       if (x+i>7) or (y-i<0) then break;
       case field[x+i,y-i] of
        BishopWhite:bit:=bit or 4;
        QueenWhite:bit:=bit or 16;
        KingWhite:if i=1 then bit:=bit or 32;
       end;
       if field[x+i,y-i]<>0 then break;
      end;
      for i:=1 to 7 do begin // влево-вверх
       if (x-i<0) or (y+i>7) then break;
       case field[x-i,y+i] of
        BishopWhite:bit:=bit or 4;
        QueenWhite:bit:=bit or 16;
        KingWhite:if i=1 then bit:=bit or 32;
       end;
       if field[x-i,y+i]<>0 then break;
      end;
      for i:=1 to 7 do begin // влево-вниз
       if (x-i<0) or (y-i<0) then break;
       case field[x-i,y-i] of
        BishopWhite:bit:=bit or 4;
        QueenWhite:bit:=bit or 16;
        KingWhite:if i=1 then bit:=bit or 32;
       end;
       if field[x-i,y-i]<>0 then break;
      end;
     end;
     if bit and 7=0 then begin // поле не бито пешкой/конём/слоном
      for i:=1 to 7 do begin // вправо
       if (x+i>7) then break;
       case field[x+i,y] of
        RookWhite:bit:=bit or 8;
        QueenWhite:bit:=bit or 16;
        KingWhite:if i=1 then bit:=bit or 32;
       end;
       if field[x+i,y]<>0 then break;
      end;
      for i:=1 to 7 do begin // влево
       if (x-i<0) then break;
       case field[x-i,y] of
        RookWhite:bit:=bit or 8;
        QueenWhite:bit:=bit or 16;
        KingWhite:if i=1 then bit:=bit or 32;
       end;
       if field[x-i,y]<>0 then break;
      end;
      for i:=1 to 7 do begin // вверх
       if (y+i>7) then break;
       case field[x,y+i] of
        RookWhite:bit:=bit or 8;
        QueenWhite:bit:=bit or 16;
        KingWhite:if i=1 then bit:=bit or 32;
       end;
       if field[x,y+i]<>0 then break;
      end;
      for i:=1 to 7 do begin // вниз
       if (y-i<0) then break;
       case field[x,y-i] of
        RookWhite:bit:=bit or 8;
        QueenWhite:bit:=bit or 16;
        KingWhite:if i=1 then bit:=bit or 32;
       end;
       if field[x,y-i]<>0 then break;
      end;
     end;
     if bit>0 then begin
      beatable[x,y]:=White+1;
      while bit and 1=0 do begin
       inc(beatable[x,y]); bit:=bit shr 1;
      end;
     end;

     bit:=0;
     // определить под боем ли поле x,y
     // пешки
     if (y<6) and (x>0) and (field[x-1,y+1]=PawnBlack) then bit:=1;
     if (y<6) and (x<7) and (field[x+1,y+1]=PawnBlack) then bit:=1;

     if bit=0 then begin // кони
      if (x>1) and (y>0) and (field[x-2,y-1]=KnightBlack) then bit:=2;
      if (x>1) and (y<7) and (field[x-2,y+1]=KnightBlack) then bit:=2;
      if (x<6) and (y>0) and (field[x+2,y-1]=KnightBlack) then bit:=2;
      if (x<6) and (y<7) and (field[x+2,y+1]=KnightBlack) then bit:=2;
      if (x>0) and (y>1) and (field[x-1,y-2]=KnightBlack) then bit:=2;
      if (x<7) and (y>1) and (field[x+1,y-2]=KnightBlack) then bit:=2;
      if (x>0) and (y<6) and (field[x-1,y+2]=KnightBlack) then bit:=2;
      if (x<7) and (y<6) and (field[x+1,y+2]=KnightBlack) then bit:=2;
     end;
     if bit=0 then begin
      for i:=1 to 7 do begin // вправо-вверх
       if (x+i>7) or (y+i>7) then break;
       case field[x+i,y+i] of
        BishopBlack:bit:=bit or 4;
        QueenBlack:bit:=bit or 16;
        KingBlack:if i=1 then bit:=bit or 32;
       end;
       if field[x+i,y+i]<>0 then break;
      end;
      for i:=1 to 7 do begin // вправо-вниз
       if (x+i>7) or (y-i<0) then break;
       case field[x+i,y-i] of
        BishopBlack:bit:=bit or 4;
        QueenBlack:bit:=bit or 16;
        KingBlack:if i=1 then bit:=bit or 32;
       end;
       if field[x+i,y-i]<>0 then break;
      end;
      for i:=1 to 7 do begin // влево-вверх
       if (x-i<0) or (y+i>7) then break;
       case field[x-i,y+i] of
        BishopBlack:bit:=bit or 4;
        QueenBlack:bit:=bit or 16;
        KingBlack:if i=1 then bit:=bit or 32;
       end;
       if field[x-i,y+i]<>0 then break;
      end;
      for i:=1 to 7 do begin // влево-вниз
       if (x-i<0) or (y-i<0) then break;
       case field[x-i,y-i] of
        BishopBlack:bit:=bit or 4;
        QueenBlack:bit:=bit or 16;
        KingBlack:if i=1 then bit:=bit or 32;
       end;
       if field[x-i,y-i]<>0 then break;
      end;
     end;
     if bit and 7=0 then begin // поле не бито пешкой/конём/слоном
      for i:=1 to 7 do begin // вправо
       if (x+i>7) then break;
       case field[x+i,y] of
        RookBlack:bit:=bit or 8;
        QueenBlack:bit:=bit or 16;
        KingBlack:if i=1 then bit:=bit or 32;
       end;
       if field[x+i,y]<>0 then break;
      end;
      for i:=1 to 7 do begin // влево
       if (x-i<0) then break;
       case field[x-i,y] of
        RookBlack:bit:=bit or 8;
        QueenBlack:bit:=bit or 16;
        KingBlack:if i=1 then bit:=bit or 32;
       end;
       if field[x-i,y]<>0 then break;
      end;
      for i:=1 to 7 do begin // вверх
       if (y+i>7) then break;
       case field[x,y+i] of
        RookBlack:bit:=bit or 8;
        QueenBlack:bit:=bit or 16;
        KingBlack:if i=1 then bit:=bit or 32;
       end;
       if field[x,y+i]<>0 then break;
      end;
      for i:=1 to 7 do begin // вниз
       if (y-i<0) then break;
       case field[x,y-i] of
        RookBlack:bit:=bit or 8;
        QueenBlack:bit:=bit or 16;
        KingBlack:if i=1 then bit:=bit or 32;
       end;
       if field[x,y-i]<>0 then break;
      end;
     end;
     if bit>0 then begin
      beatable[x,y]:=beatable[x,y] or (Black+$8);
      while bit and 1=0 do begin
       inc(beatable[x,y],$8); bit:=bit shr 1;
      end;
     end;
    end;
  end;

 procedure AddMove(m:byte); inline;
  begin
   inc(mCount);
   moves[mCount]:=m;
  end;

 procedure GetAvailMoves(var board:TBoard;piece:byte);
  var
   i,j,x,y:integer;
   v,color,color2,m,n,l:byte;
  begin
   mCount:=0;
   with board do begin
    x:=piece and $F;
    y:=piece shr 4;
    v:=field[x,y] and $F;
    color:=field[x,y] and ColorMask;
    if v=Pawn then begin
      if color=White then begin
       // белая пешка
       if (y<7) and (field[x,y+1]=0) then AddMove(piece+$10);
       if (y=1) and (field[x,2]=0) and (field[x,3]=0) then AddMove(piece+$20);
       if (x>0) and (field[x-1,y+1] and ColorMask=Black) then AddMove(piece+$10-1);
       if (x<7) and (field[x+1,y+1] and ColorMask=Black) then AddMove(piece+$10+1);
       // взятие на проходе
       if (y=4) and (x>0) and (field[x-1,y]=PawnBlack) and
         (lastTurnFrom=piece+$20-1) and (lastTurnTo=piece-1) then AddMove(piece+$10-1);
       if (y=4) and (x<70) and (field[x+1,y]=PawnBlack) and
         (lastTurnFrom=piece+$20+1) and (lastTurnTo=piece+1) then AddMove(piece+$10+1);
      end else begin
       // черная пешка
       if (y>0) and (field[x,y-1]=0) then AddMove(piece-$10);
       if (y=6) and (field[x,5]=0) and (field[x,4]=0) then AddMove(piece-$20);
       if (x>0) and (field[x-1,y-1] and ColorMask=White) then AddMove(piece-$10-1);
       if (x<7) and (field[x+1,y-1] and ColorMask=White) then AddMove(piece-$10+1);
       // взятие на проходе
       if (y=3) and (x>0) and (field[x-1,y]=PawnWhite) and
         (lastTurnFrom=piece-$20-1) and (lastTurnTo=piece-1) then AddMove(piece-$10-1);
       if (y=3) and (x<70) and (field[x+1,y]=PawnWhite) and
         (lastTurnFrom=piece-$20+1) and (lastTurnTo=piece+1) then AddMove(piece-$10+1);
      end;
      exit;
     end;

    if v=Knight then begin
     if (x>0) and (y>1) and (field[x-1,y-2] and ColorMask<>color) then AddMove(piece-$20-1);
     if (x<7) and (y>1) and (field[x+1,y-2] and ColorMask<>color) then AddMove(piece-$20+1);

     if (x>0) and (y<6) and (field[x-1,y+2] and ColorMask<>color) then AddMove(piece+$20-1);
     if (x<7) and (y<6) and (field[x+1,y+2] and ColorMask<>color) then AddMove(piece+$20+1);

     if (x>1) and (y>0) and (field[x-2,y-1] and ColorMask<>color) then AddMove(piece-$10-2);
     if (x>1) and (y<7) and (field[x-2,y+1] and ColorMask<>color) then AddMove(piece+$10-2);

     if (x<6) and (y>0) and (field[x+2,y-1] and ColorMask<>color) then AddMove(piece-$10+2);
     if (x<6) and (y<7) and (field[x+2,y+1] and ColorMask<>color) then AddMove(piece+$10+2);
     exit;
    end;

    if v=King then begin
     // нельзя ходить на поле под боем
     if color=white then color2:=black else color2:=white;
     field[x,y]:=0;
     CalcBeatable(board);
     field[x,y]:=King+color;
     if (x>0) and (y>0) and (field[x-1,y-1] and ColorMask<>color) and (beatable[x-1,y-1] and color2=0) then AddMove(piece-$10-1);
     if (x>0) and (y<7) and (field[x-1,y+1] and ColorMask<>color) and (beatable[x-1,y+1] and color2=0) then AddMove(piece+$10-1);
     if (x<7) and (y>0) and (field[x+1,y-1] and ColorMask<>color) and (beatable[x+1,y-1] and color2=0) then AddMove(piece-$10+1);
     if (x<7) and (y<7) and (field[x+1,y+1] and ColorMask<>color) and (beatable[x+1,y+1] and color2=0) then AddMove(piece+$10+1);

     if (x>0) and (field[x-1,y] and ColorMask<>color) and (beatable[x-1,y] and color2=0) then AddMove(piece-1);
     if (x<7) and (field[x+1,y] and ColorMask<>color) and (beatable[x+1,y] and color2=0) then AddMove(piece+1);
     if (y>0) and (field[x,y-1] and ColorMask<>color) and (beatable[x,y-1] and color2=0) then AddMove(piece-$10);
     if (y<7) and (field[x,y+1] and ColorMask<>color) and (beatable[x,y+1] and color2=0) then AddMove(piece+$10);

     // Рокировка...
     if (x=4) and (y=0) and (color=White) and (rFlags and $F<3) then begin
      // Возможна рокировка хотя бы в одну сторону
      // длинная рокировка
      if (rFlags and 1=0) and (field[1,0] or field[2,0] or field[3,0]=0) and
         ((beatable[2,0] or beatable[3,0] or beatable[4,0]) and Black=0) then
           AddMove(piece-2);
      // короткая рокировка
      if (rFlags and 2=0) and (field[5,0] or field[6,0]=0) and
         ((beatable[4,0] or beatable[5,0] or beatable[6,0]) and Black=0) then
           AddMove(piece+2);
     end;
     if (x=4) and (y=7) and (color=Black) and (rFlags and $F0<$30) then begin
      // Возможна рокировка хотя бы в одну сторону
      // длинная рокировка
      if (rFlags and $10=0) and (field[1,7] or field[2,7] or field[3,7]=0) and
         ((beatable[2,7] or beatable[3,7] or beatable[4,7]) and White=0) then
           AddMove(piece-2);
      // короткая рокировка
      if (rFlags and $20=0) and (field[5,7] or field[6,7]=0) and
         ((beatable[4,7] or beatable[5,7] or beatable[6,7]) and White=0) then
           AddMove(piece+2);
     end;
     exit;
    end;

    if v in [Rook,Queen] then begin
      // ладья
      m:=piece;
      for i:=x+1 to 7 do begin
       if field[i,y] and ColorMask=color then break;
       m:=m+1;
       AddMove(m);
       if field[i,y]<>0 then break;
      end;
      m:=piece;
      for i:=x-1 downto 0 do begin
       if field[i,y] and ColorMask=color then break;
       m:=m-1;
       AddMove(m);
       if field[i,y]<>0 then break;
      end;
      m:=piece;
      for i:=y+1 to 7 do begin
       if field[x,i] and ColorMask=color then break;
       m:=m+$10;
       AddMove(m);
       if field[x,i]<>0 then break;
      end;
      m:=piece;
      for i:=y-1 downto 0 do begin
       if field[x,i] and ColorMask=color then break;
       m:=m-$10;
       AddMove(m);
       if field[x,i]<>0 then break;
      end;
     end;

    if v in [Bishop,Queen] then begin
     // Слон
     m:=piece;
     n:=x; l:=y;
     for i:=1 to 7 do begin
      inc(n); inc(l);
      m:=m+$10+1;
      if (n>7) or (l>7) or (field[n,l] and ColorMask=color) then break;
      AddMove(m);
      if field[n,l]<>0 then break;
     end;
     m:=piece;
     n:=x; l:=y;
     for i:=1 to 7 do begin
      dec(n); inc(l);
      m:=m+$10-1;
      if (n>7) or (l>7) or (field[n,l] and ColorMask=color) then break;
      AddMove(m);
      if field[n,l]<>0 then break;
     end;
     m:=piece;
     n:=x; l:=y;
     for i:=1 to 7 do begin
      inc(n); dec(l);
      m:=m-$10+1;
      if (n>7) or (l>7) or (field[n,l] and ColorMask=color) then break;
      AddMove(m);
      if field[n,l]<>0 then break;
     end;
     m:=piece;
     n:=x; l:=y;
     for i:=1 to 7 do begin
      dec(n); dec(l);
      m:=m-$10-1;
      if (n>7) or (l>7) or (field[n,l] and ColorMask=color) then break;
      AddMove(m);
      if field[n,l]<>0 then break;
     end;
    end;
   end;
  end;

 procedure DoMove(var board:TBoard;from,target:byte);
  var
   x,y,nx,ny:integer;
   v:byte;
  begin
   with board do begin
    x:=from and $F;
    y:=from shr 4;
    nx:=target and $F;
    ny:=target shr 4;
    v:=field[x,y];
    field[x,y]:=0;
    lastPiece:=field[nx,ny];
    if field[nx,ny]>0 then flags:=flags or movBeat
     else flags:=flags and (not movBeat);
    field[nx,ny]:=v;
    // пешка -> ферзь
    if (v=PawnWhite) and (ny=7) then field[nx,ny]:=QueenWhite;
    if (v=PawnBlack) and (ny=0) then field[nx,ny]:=QueenBlack;
    // пешка на проходе
    if (ny=2) and (field[nx,ny+1]=PawnWhite) and (LastTurnFrom=nx+(ny-1) shl 4)
     and (LastTurnTo=nx+(ny+1) shl 4) then begin
      field[nx,ny+1]:=0; board.flags:=board.flags or movBeat;
    end;
    if (ny=5) and (field[nx,ny-1]=PawnBlack) and (LastTurnFrom=nx+(ny+1) shl 4)
     and (LastTurnTo=nx+(ny-1) shl 4) then begin
      field[nx,ny-1]:=0;
    end;

    if v and $F=King then begin
     if v and ColorMask=White then
      rFlags:=rFlags or $4
     else
      rFlags:=rFlags or $40;
     // Рокировка
     if (x=4) and (nx=2) then begin
      field[3,y]:=field[0,y];
      field[0,y]:=0;
      if y=0 then rFlags:=rFlags or $8
       else rFlags:=rFlags or $80;
     end;
     if (x=4) and (nx=6) then begin
      field[5,y]:=field[7,y];
      field[7,y]:=0;
      if y=0 then rFlags:=rFlags or $8
       else rFlags:=rFlags or $80;
     end;
    end;

    if v and $F=Rook then
     if x=0 then begin
      if (y=0) and (v and ColorMask=White) then rFlags:=rFlags or 1;
      if (y=7) and (v and ColorMask=Black) then rFlags:=rFlags or $10;
     end else
     if x=7 then begin
      if (y=0) and (v and ColorMask=White) then rFlags:=rFlags or 2;
      if (y=7) and (v and ColorMask=Black) then rFlags:=rFlags or $20;
     end;

    WhiteTurn:=not WhiteTurn;
    LastTurnFrom:=from;
    LastTurnTo:=target;
   end;
  end;

 procedure InitBoard(var board:TBoard);
  var
   i:integer;
  begin
   fillchar(board.field,64,0);
   with board do begin
    for i:=0 to 7 do begin
     field[i,1]:=PawnWhite;
     field[i,6]:=PawnBlack;
    end;
    field[0,0]:=$42; field[0,7]:=$82;
    field[1,0]:=$43; field[1,7]:=$83;
    field[2,0]:=$44; field[2,7]:=$84;
    field[3,0]:=$45; field[3,7]:=$85;
    field[4,0]:=$46; field[4,7]:=$86;
    field[5,0]:=$44; field[5,7]:=$84;
    field[6,0]:=$43; field[6,7]:=$83;
    field[7,0]:=$42; field[7,7]:=$82;
    WhiteTurn:=true;
    WhiteRate:=0;
    BlackRate:=0;
    parent:=0;
    rFlags:=0;
   end;
   historyPos:=0; // нет предыдущих состояний
   gameover:=0;
  end;

// проверяет был ли поставлен шах последним ходом и устанавливает флаг шаха если был
function IsCheck(var b:TBoard):boolean;
var
 i,j,k:integer;
 fl:boolean;
label check;
begin
 with b do begin
  if WhiteTurn then
  for i:=0 to 7 do
   for j:=0 to 7 do
    if field[i,j]=KingWhite then begin
     // ладьей или ферзем вверх
     for k:=j+1 to 7 do
      if field[i,k] in [QueenBlack,RookBlack] then goto check
       else if field[i,k]>0 then break;
     // ладьей или ферзем вправо
     for k:=i+1 to 7 do
      if field[k,j] in [QueenBlack,RookBlack] then goto check
       else if field[k,j]>0 then break;
     // ладьей или ферзем влево
     for k:=i-1 downto 0 do
      if field[k,j] in [QueenBlack,RookBlack] then goto check
       else if field[k,j]>0 then break;
     // ладьей или ферзем вниз
     for k:=j-1 downto 0 do
      if field[i,k] in [QueenBlack,RookBlack] then goto check
       else if field[i,k]>0 then break;

     // слоном или ферзем вверх-вправо
     for k:=1 to 7 do
      if (i+k>7) or (j+k>7) then break else
       if field[i+k,j+k] in [QueenBlack,BishopBlack] then goto check
        else if field[i+k,j+k]>0 then break;
     // слоном или ферзем вверх-влево
     for k:=1 to 7 do
      if (i-k<0) or (j+k>7) then break else
       if field[i-k,j+k] in [QueenBlack,BishopBlack] then goto check
        else if field[i-k,j+k]>0 then break;
     // слоном или ферзем вниз-вправо
     for k:=1 to 7 do
      if (i+k>7) or (j-k<0) then break else
       if field[i+k,j-k] in [QueenBlack,BishopBlack] then goto check
        else if field[i+k,j-k]>0 then break;
     // слоном или ферзем вниз-влево
     for k:=1 to 7 do
      if (i-k<0) or (j-k<0) then break else
       if field[i-k,j-k] in [QueenBlack,BishopBlack] then goto check
        else if field[i-k,j-k]>0 then break;

     // конём
     if i-1>=0 then begin
      if (j-2>=0) and (field[i-1,j-2]=KnightBlack) then goto check;
      if (j+2<=7) and (field[i-1,j+2]=KnightBlack) then goto check;
     end;
     if i-2>=0 then begin
      if (j-1>=0) and (field[i-2,j-1]=KnightBlack) then goto check;
      if (j+1<=7) and (field[i-2,j+1]=KnightBlack) then goto check;
     end;
     if i+1<=7 then begin
      if (j-2>=0) and (field[i+1,j-2]=KnightBlack) then goto check;
      if (j+2<=7) and (field[i+1,j+2]=KnightBlack) then goto check;
     end;
     if i+2<=7 then begin
      if (j-1>=0) and (field[i+2,j-1]=KnightBlack) then goto check;
      if (j+1<=7) and (field[i+2,j+1]=KnightBlack) then goto check;
     end;

     // Пешкой
     if (j<6) then begin
      if (i>0) and (field[i-1,j+1]=pawnBlack) then goto check;
      if (i<7) and (field[i+1,j+1]=pawnBlack) then goto check;
     end;
    end;
    
  // Если ход черных - проверить черного короля
  if not WhiteTurn then
  for i:=0 to 7 do
   for j:=0 to 7 do
    if field[i,j]=KingBlack then begin
     // ладьей или ферзем вниз
     for k:=j-1 downto 0 do
      if field[i,k] in [QueenWhite,RookWhite] then goto check
       else if field[i,k]>0 then break;
     // ладьей или ферзем вправо
     for k:=i+1 to 7 do
      if field[k,j] in [QueenWhite,RookWhite] then goto check
       else if field[k,j]>0 then break;
     // ладьей или ферзем влево
     for k:=i-1 downto 0 do
      if field[k,j] in [QueenWhite,RookWhite] then goto check
       else if field[k,j]>0 then break;
     // ладьей или ферзем вверх
     for k:=j+1 to 7 do
      if field[i,k] in [QueenWhite,RookWhite] then goto check
       else if field[i,k]>0 then break;

     // слоном или ферзем вниз-вправо
     for k:=1 to 7 do
      if (i+k>7) or (j-k<0) then break else
       if field[i+k,j-k] in [QueenWhite,BishopWhite] then goto check
        else if field[i+k,j-k]>0 then break;
     // слоном или ферзем вниз-влево
     for k:=1 to 7 do
      if (i-k<0) or (j-k<0) then break else
       if field[i-k,j-k] in [QueenWhite,BishopWhite] then goto check
        else if field[i-k,j-k]>0 then break;
     // слоном или ферзем вверх-вправо
     for k:=1 to 7 do
      if (i+k>7) or (j+k>7) then break else
       if field[i+k,j+k] in [QueenWhite,BishopWhite] then goto check
        else if field[i+k,j+k]>0 then break;
     // слоном или ферзем вверх-влево
     for k:=1 to 7 do
      if (i-k<0) or (j+k>7) then break else
       if field[i-k,j+k] in [QueenWhite,BishopWhite] then goto check
        else if field[i-k,j+k]>0 then break;

     // конём
     if i-1>=0 then begin
      if (j-2>=0) and (field[i-1,j-2]=KnightWhite) then goto check;
      if (j+2<=7) and (field[i-1,j+2]=KnightWhite) then goto check;
     end;
     if i-2>=0 then begin
      if (j-1>=0) and (field[i-2,j-1]=KnightWhite) then goto check;
      if (j+1<=7) and (field[i-2,j+1]=KnightWhite) then goto check;
     end;
     if i+1<=7 then begin
      if (j-2>=0) and (field[i+1,j-2]=KnightWhite) then goto check;
      if (j+2<=7) and (field[i+1,j+2]=KnightWhite) then goto check;
     end;
     if i+2<=7 then begin
      if (j-1>=0) and (field[i+2,j-1]=KnightWhite) then goto check;
      if (j+1<=7) and (field[i+2,j+1]=KnightWhite) then goto check;
     end;

     // Пешкой
     if (j>1) then begin
      if (i>0) and (field[i-1,j-1]=pawnWhite) then goto check;
      if (i<7) and (field[i+1,j-1]=pawnWhite) then goto check;
     end;
    end;
 end;

 exit;
check:
 b.flags:=b.flags or movCheck;
end;

// Оценивает позицию
procedure EstimatePosition(var b:TBoard;quality:byte;noCache:boolean=false);
const
 PawnRate:array[0..7] of single=(1, 1, 1, 1.02, 1.1, 1.3, 1.9, 2);
var
 i,j,n,m,x,y,f:integer;
 v:single;
 maxblack,maxwhite:single;
 hash:int64;
 h:integer;
begin
 inc(estCounter);
 // проверка на 3-й повтор
 n:=1;
 j:=b.parent;
 while j>0 do begin
  if CompareBoards(b,data[j])=0 then inc(n);
  j:=data[j].parent;
 end;
 for j:=1 to historyPos do
  if compareBoards(b,history[j])=0 then inc(n);
 if n>=3 then begin
  b.BlackRate:=1;
  b.WhiteRate:=1;
  b.rate:=0;
  b.flags:=b.flags or movRepeat;
  exit;
 end;

 if not noCache then begin
  inc(cacheUse);
  hash:=BoardHash(b);
  h:=hash and CacheMask;
  if cache[h].hash=hash then with b do begin
   // вычисление флага шаха
   IsCheck(b);
   whiterate:=1;
   blackrate:=1;
   rate:=integer(cache[h].rate and $FFFFFF00)/(1000*256);
   if cache[h].rate and 1>0 then flags:=flags or movDB;
   if PlayerWhite then rate:=-rate;
   exit;
  end;
 end;

 with b do begin
  WhiteRate:=-1000;
  BlackRate:=-1000;
  flags:=flags and (not movCheck);
  if quality=0 then begin
   for i:=0 to 7 do
    for j:=0 to 7 do
     case field[i,j] of
      KingWhite:WhiteRate:=WhiteRate+1000;
      KingBlack:BlackRate:=BlackRate+1000;
     end;
   exit;
  end;
  CalcBeatable(b);
  // Базовая оценка
  for i:=0 to 7 do
   for j:=0 to 7 do
    case field[i,j] of
     PawnWhite:WhiteRate:=WhiteRate+PawnRate[j];
     PawnBlack:BlackRate:=BlackRate+PawnRate[7-j];

     RookWhite:WhiteRate:=WhiteRate+5;
     RookBlack:BlackRate:=BlackRate+5;
     QueenWhite:WhiteRate:=WhiteRate+9;
     QueenBlack:BlackRate:=BlackRate+9;
     BishopWhite:WhiteRate:=WhiteRate+3;
     BishopBlack:BlackRate:=BlackRate+3;
     KnightWhite:WhiteRate:=WhiteRate+3;
     KnightBlack:BlackRate:=BlackRate+3;
     // если король под шахом и ход противника - игра проиграна
     KingWhite:begin
      // условие инвертировано
      if WhiteTurn or (beatable[i,j] and Black=0) then WhiteRate:=WhiteRate+1005;
      if beatable[i,j] and Black>0 then flags:=flags or movCheck;
     end;
     KingBlack:begin
      if not WhiteTurn or (beatable[i,j] and White=0) then BlackRate:=BlackRate+1005;
      if beatable[i,j] and White>0 then flags:=flags or movCheck;
     end;
    end;
  // Бонус за рокировку
  if rFlags and $8>0 then WhiteRate:=WhiteRate+0.8;
  if rFlags and $80>0 then BlackRate:=BlackRate+0.8;
  // Штраф за невозможность рокировки
  if (rFlags and $8=0) and (rflags and $4>0) then WhiteRate:=WhiteRate-0.3;
  if (rFlags and $80=0) and (rflags and $40>0) then BlackRate:=BlackRate-0.3;

  if gamestage<3 then begin
   // Штраф за невыведенные фигуры
   if field[1,0]=KnightWhite then WhiteRate:=WhiteRate-0.2;
   if field[6,0]=KnightWhite then WhiteRate:=WhiteRate-0.2;
   if field[2,0]=BishopWhite then WhiteRate:=WhiteRate-0.2;
   if field[5,0]=BishopWhite then WhiteRate:=WhiteRate-0.2;
   if field[1,7]=KnightBlack then BlackRate:=BlackRate-0.2;
   if field[6,7]=KnightBlack then BlackRate:=BlackRate-0.2;
   if field[2,7]=BishopBlack then BlackRate:=BlackRate-0.2;
   if field[5,7]=BishopBlack then BlackRate:=BlackRate-0.2;
   // штраф за гуляющего короля
   for i:=0 to 7 do
    for j:=1 to 6 do begin
     if field[i,j]=KingWhite then WhiteRate:=WhiteRate-sqr(j)*0.05;
     if field[i,j]=KingBlack then BlackRate:=BlackRate-sqr(7-j)*0.05;
    end;
  end;
  // штраф за сдвоенные пешки и бонус за захват открытых линий
  for i:=0 to 7 do begin
   n:=0; m:=0; f:=0;
   for j:=0 to 7 do begin
    if field[i,j]=PawnWhite then inc(n);
    if field[i,j]=PawnBlack then inc(m);
    if field[i,j] in [RookWhite,QueenWhite] then f:=f or 1;
    if field[i,j] in [RookBlack,QueenBlack] then f:=f or 2;
   end;
   if n>1 then WhiteRate:=WhiteRate-0.1*n;
   if m>1 then BlackRate:=BlackRate-0.1*m;
   if (n=0) and (m=0) and (f and 1>0) then WhiteRate:=WhiteRate+0.1;
   if (n=0) and (m=0) and (f and 2>0) then BlackRate:=BlackRate+0.1;
  end;

  // Надбавка за инициативу
{  if WhiteTurn then WhiteRate:=WhiteRate+0.1
   else BlackRate:=BlackRate+0.05;}

  if quality>0 then begin
   // 1-е расширение оценки - поля и фигуры под боем
   maxblack:=0; maxwhite:=0;
   for i:=0 to 7 do
    for j:=0 to 7 do begin
     v:=0.08;
     if (i in [2..5]) and (j in [2..5]) then v:=0.09;
     if (i in [3..4]) and (j in [3..4]) then v:=0.11;
     if beatable[i,j] and White>0 then WhiteRate:=WhiteRate+v;
     if beatable[i,j] and Black>0 then BlackRate:=BlackRate+v;
     // Незащищенная фигура под боем на ходу противника - минус фигуру!
     if (b.WhiteTurn) and (beatable[i,j] and White>0) and (field[i,j] and ColorMask=Black) then begin
      if beatable[i,j] and Black>0 then v:=bweight[field[i,j] and $F]-bweight2[beatable[i,j] and 7]
       else v:=bweight[field[i,j] and $F];
      if maxblack<v then maxblack:=v;
     end;
     if (not b.WhiteTurn) and (beatable[i,j] and Black>0) and (field[i,j] and ColorMask=White) then begin
      if beatable[i,j] and White>0 then v:=bweight[field[i,j] and $F]-bweight2[(beatable[i,j] shr 3) and 7]
       else v:=bweight[field[i,j] and $F];
      if maxWhite<v then maxWhite:=v;
     end;
    end;
   WhiteRate:=WhiteRate-maxWhite;
   BlackRate:=BlackRate-maxBlack;
  end;

  if WhiteRate<5.5 then begin // один король
   for i:=0 to 7 do
    for j:=0 to 7 do
     if field[i,j]=KingWhite then begin
      x:=i; y:=j;
      WhiteRate:=WhiteRate-0.2*(abs(i-3.5)+abs(j-3.5));
     end;
   for i:=0 to 7 do
    for j:=0 to 7 do
     if field[i,j]=KingBlack then
      BlackRate:=BlackRate-0.05*(abs(i-x)+abs(j-y));
  end;
  if BlackRate<5.5 then begin // один король
   for i:=0 to 7 do
    for j:=0 to 7 do
     if field[i,j]=KingBlack then begin
      x:=i; y:=j;
      BlackRate:=BlackRate-0.2*(abs(i-3.5)+abs(j-3.5));
     end;
   for i:=0 to 7 do
    for j:=0 to 7 do
     if field[i,j]=KingWhite then
      WhiteRate:=WhiteRate-0.05*(abs(i-x)+abs(j-y));
  end;

  rate:=(WhiteRate-BlackRate)*(1+10/(BlackRate+WhiteRate));
{   rate:=(BlackRate-WhiteRate)*(1+1/(BlackRate+WhiteRate))+random(3)/2000
  else
   rate:=(WhiteRate-BlackRate)*(1+1/(BlackRate+WhiteRate))+random(3)/2000;}

  if not noCache then begin
   cache[h].hash:=hash;
   cache[h].rate:=round(rate*1000) shl 8;
   inc(cacheMiss);
  end;

  if PlayerWhite then rate:=-rate;
 end;
end;

procedure GetGamePhase;
var
 i,j:integer;
 c:integer;
begin
 c:=0;
 for i:=0 to 7 do begin
  if board.field[i,0]>0 then inc(c);
  if board.field[i,7]>0 then inc(c);
  if board.field[i,1]=PawnWhite then inc(c);
  if board.field[i,6]=PawnBlack then inc(c);
 end;
 if c>=18 then begin
  gamestage:=1; exit; // дебют
 end;
 EstimatePosition(board,10,true);
 if (board.WhiteRate<18) and (board.BlackRate<18) then gameStage:=3
  else gamestage:=2;
end;

{ Thread }

procedure ThinkThread.Reset;
begin
 moveReady:=false;
 gameover:=0;
 useLibrary:=true;
end;

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
procedure DeleteNode(node:integer;fixlinks:boolean=true);
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
 if fixlinks then with data[node] do begin
  if prev>0 then data[prev].next:=next;
  if next>0 then data[next].prev:=prev;
  if (parent>0) then begin
   if data[parent].firstChild=node then data[parent].firstChild:=next;
   if data[parent].lastChild=node then data[parent].lastChild:=prev;
  end;
 end;
end;

// Построить полное дерево до заданной глубины
// продолжать ходы со взятием и шахами, но не далее чем до maxdepth
// корневой эл-т должен быть оценен!
procedure BuildTree(root:integer;forHuman:boolean=false);
var
 i,j,k,newidx,h,cur:integer;
 hash:int64;
 color:byte;
begin
 qstart:=1; qLast:=2;
 qu[qstart]:=root;
 repeat
  cur:=qu[qStart];
  with data[cur] do begin
   // не продолжать позиции, которые:
   // - являются проигрышными для одной из сторон
   // - уже имеют потомков, т.е. были обработаны ранее
   // - приводят к пату из-за повторения позиций
   // - с оценкой из базы
   if (rate>-200) and (rate<200) and (flags and (movRepeat+movDB)=0) then begin
    if firstChild>0 then begin
     k:=firstChild;
     while k>0 do begin
      qu[qLast]:=k;
      inc(qLast);
      k:=data[k].next;
     end;
     inc(qStart); continue;
    end;
    if weight<=0 then begin
     inc(qStart);
     continue;
    end;
    if (flags and movCheck>0) then begin
     if depth and 1=0 then rate:=-300+depth else rate:=300-depth;
    end else rate:=0; // оценка будет сформирована из потомков, если их нет - пат=0
    if WhiteTurn then color:=White else color:=Black;
    // продолжить дерево
    for i:=0 to 7 do
     for j:=0 to 7 do
      if field[i,j] and ColorMask=color then begin
       getAvailMoves(data[cur],i+j shl 4);
       for k:=1 to mCount do begin
        if freecnt<1 then break;
        newidx:=AddChild(cur);
        data[newidx].field:=field;
        data[newidx].rFlags:=rFlags;
        data[newidx].depth:=depth+1;
        data[newidx].WhiteTurn:=WhiteTurn;
        DoMove(data[newidx],i+j shl 4,moves[k]);
        qu[qLast]:=newidx;
        inc(qLast);
        EstimatePosition(data[newidx],10);
        if data[newidx].flags and movBeat>0 then
         data[newidx].weight:=weight-6
        else
        if data[newidx].flags and movCheck>0 then
         data[newidx].weight:=weight-2
        else
         data[newidx].weight:=weight-10;
        if abs(data[newidx].rate)>200 then begin
         // недопустимый ход
         DeleteNode(newidx,true);
         dec(qLast);
        end;
       end;
      end;
   end;
  end;
  inc(qStart);
 until qStart=qLast;
end;

function CalcLeafs(root:integer):integer;
var
 d:integer;
begin
 result:=0;
 d:=data[root].firstChild;
 if d=0 then begin
  result:=1; exit;
 end;
 while d>0 do begin
  inc(result,CalcLeafs(d));
  d:=data[d].next;
 end;
end;

procedure CheckTree(root:integer);
var
 c:integer;
begin
 data[root].flags:=data[root].flags or $80;
 c:=data[root].firstChild;
 while c>0 do begin
  CheckTree(c);
  Assert(data[c].parent=root);
  c:=data[c].next;
 end;
end;

procedure SortChildren(root:integer);
var
 children:array[1..120] of integer;
 i,j,d,n,c:integer;
begin
 n:=0;
 c:=data[root].firstChild;
 if c=0 then exit;
 while c>0 do begin
  inc(n);
  children[n]:=c;
  c:=data[c].next;
 end;
 for i:=1 to n-1 do
  for j:=i+1 to n do
   if data[children[j]].rate>data[children[i]].rate then begin
    d:=children[i];
    children[i]:=children[j];
    children[j]:=d;
   end;
 c:=children[1];
 data[root].firstChild:=c;
 data[c].prev:=0;
 d:=c;
 for i:=2 to n do begin
  c:=children[i];
  data[c].prev:=d;
  data[d].next:=c;
  d:=c;
 end;
 data[c].next:=0;
 data[root].lastChild:=c;
end;

// Обрезание дерева
procedure CutTree(root:integer;p1,p2:integer);
var
 i,j,d:integer;
 v,v2,gate,gate2:single;
 dir,fl:boolean;
begin
 SortChildren(root);
// t1:=p1 div (data[root].depth+p2);
// t2:=(p1+20) div (data[root].depth+p2-1);

 dir:=data[root].depth and 1=0;
 if dir then d:=data[root].firstChild
   else d:=data[root].lastChild;

 j:=1; v:=0; gate:=(4+sqr(data[root].depth))/p1; gate2:=gate*0.5;
 v2:=data[root].rate; v:=v2;
 fl:=false;
 while d>0 do begin
  if (abs(data[d].rate-v2)>gate) and fl then
      DeleteNode(d)
    else begin
     CutTree(d,p1,p2);
     gate2:=gate2*0.6+0.01;
    end;
  v:=data[d].rate;
  if dir then d:=data[d].next else d:=data[d].prev;
  if abs(data[d].rate-v)>gate2 then fl:=true;
  inc(j);
 end;

end;

procedure RateTree(root:integer;leafweight:shortint=10;delbad:boolean=false);
var
 children:array[1..120] of integer;
 i,d,n,c:integer;
 min,max,v:single;
begin
 d:=data[root].firstChild;
 n:=0;
 while d>0 do begin
  inc(n);
  if data[d].firstChild>0 then
   RateTree(d,leafweight,delbad)
  else
   data[d].Weight:=leafWeight;
  children[n]:=d;
  d:=data[d].next;
 end;
 if n=0 then exit;
 min:=data[children[1]].rate;
 max:=min;
 for i:=2 to n do begin
  v:=data[children[i]].rate;
  if v>max then max:=v;
  if v<min then min:=v;
 end;
 if data[root].depth and 1=0 then
  data[root].rate:=max
 else
  data[root].rate:=min;

{ if delbad then begin
  // прореживание дерева
  c:=n;
  if data[root].depth and 1=0 then begin
   v:=(max+min)/2;
   while c>(25 div (data[root].depth+2)) do begin
    for i:=1 to n do
     if (children[i]>0) and (data[children[i]].rate<v) then begin
      DeleteNode(children[i]); children[i]:=0; dec(c);
     end;
    v:=(v*3+max)/4;
   end;
  end else begin
   v:=(max+min)/2;
   while c>(25 div (data[root].depth+2)) do begin
    for i:=1 to n do
     if (children[i]>0) and (data[children[i]].rate>v) then begin
      DeleteNode(children[i]); children[i]:=0; dec(c);
     end;
    v:=(v*3+min)/4;
   end;
  end;
 end; }
end;

//
function ThinkThread.ThinkIteration(root:integer;iteration:byte):boolean;
var
 i,j,c,limit:integer;
 arr:array[1..100] of integer;
begin
 result:=true;
 case iteration of
  1:begin
   BuildTree(root);
   RateTree(root);
  end;
  2..19:begin
   if data[root].firstChild=data[root].lastChild then begin
    result:=false; exit;
   end;
   limit:=8*(220*level+500);
   if limit>20000 then limit:=20000;
   leafs:=CalcLeafs(root);
   if leafs>limit then begin
    CutTree(root,8,0);
    leafs:=CalcLeafs(root);
   end;
   if leafs>limit then begin
    CutTree(root,20,0);
    leafs:=CalcLeafs(root);
   end;
   if leafs>limit then begin
    CutTree(root,40,0);
    leafs:=CalcLeafs(root);
   end;
   if leafs>limit then begin
    result:=false; exit;
   end;
   inc(d1); inc(d2);
   if leafs<limit div 10 then
    BuildTree(root)
   else
    BuildTree(root);
   RateTree(root);
  end;
 end;
end;

// Найти ход
procedure ThinkThread.DoThink;
var
 startTime,limit:cardinal;
 i,j,n:integer;
 turns:array[1..30] of integer;
 weight:integer;
 b:TBoard;
 color,color2,phase:byte;
 v:single;
 hash:int64;
 fl:boolean;
begin
 starttime:=gettickcount;

 if PlayerWhite then begin
  color:=Black; color2:=white;
 end else begin
  color:=White; color2:=black;
 end;

 // 1. Поиск ходов в библиотеке
 if useLibrary then begin
  n:=0; weight:=0;
  for i:=0 to length(turnLib)-1 do
   if CompareBoards(board,turnLib[i])=0 then begin
    inc(n);
    turns[n]:=i;
    inc(weight,turnlib[i].weight);
   end;
  if n>0 then begin
   j:=random(weight);
   weight:=0;
   for i:=1 to n do begin
    weight:=weight+turnlib[turns[i]].weight;
    if weight>j then begin
     moveFrom:=turnlib[turns[i]].lastTurnFrom;
     moveTo:=turnlib[turns[i]].lastTurnTo;
     moveReady:=true;
     exit;
    end;
   end;
  end;
 end;
 // 2. Обдумывание
 // определение фазы игры
 GetGamePhase;

 // 2.1. Составить все различные позиции на 3 полухода вперед
 status:='Составление позиций';
 try
 qStart:=1; // текущий эл-т для обработки
 qlast:=1; // последний добавленный в очередь эл-т
 freecnt:=0;
 for i:=memsize downto 1 do begin
  inc(freecnt);
  freeList[freecnt]:=i;
 end;
 dec(freecnt);
 data[1]:=board;
 data[1].depth:=0;
 data[1].weight:=26;
 data[1].parent:=0;
 data[1].next:=0;
 data[1].firstChild:=0;
 data[1].lastChild:=0;
 EstimatePosition(data[1],10);
 data[1].flags:=0;
// data[1].flags:=data[1].flags and not movDB;
 cacheUse:=0; cacheMiss:=0;
 estCounter:=0;

 phase:=0;
 if level=0 then begin
  // упрощенный уровень
  BuildTree(1);
  RateTree(1,10);
 end else begin
  // обычный уровень
  case level of
   1:limit:=100000;
   2:limit:=500000;
   3:limit:=2000000;
  end;
  d1:=3; d2:=4;
  for i:=1 to 11 do begin
   phase:=i;
   status:='Фаза '+inttostr(i);
   if not ThinkIteration(1,i) then begin
    dec(phase);
    break;
   end;
   if (plimit>0) and (i>=plimit) then break;
   if (estCounter>limit) or (terminated) then break;
  end;
 end;
 leafs:=CalcLeafs(1);

{ status:='Углублённая проработка';
 BuildTree(1,5,6);
 RateTree(1,false);}
 v:=0;
 if cacheUse>0 then v:=(cacheUse-cacheMiss)/cacheUse;
 status:='Фаз: '+inttostr(phase)+
  '. Поз: '+inttostr(estCounter)+' / '+inttostr(memsize-freeCnt)+
  ' / '+inttostr(leafs)+
  ', кэш: '+floattostrf(v,ffFixed,3,2)+
  '. Время: '+FloatToStrF((GetTickCount-startTime)/1000,ffFixed,3,1);

 // Выбор оптимального хода
 if data[1].firstChild=0 then begin
  // нет ходов
  CalcBeatable(data[1]);
  gameover:=1; // пат
  for i:=0 to 7 do
   for j:=0 to 7 do
    if (data[1].field[i,j]=King+color) and (beatable[i,j] and color2>0) then
     gameover:=2; // мат
  terminate;
  exit;
 end else begin
  // Ходы есть - выбрать лучший
  i:=data[1].firstChild;
  j:=i;
  while i>0 do begin
   if data[i].rate=data[1].rate then begin
    j:=i; break;
   end; 
   i:=data[i].next;
  end;
 end;

 if abs(data[j].rate)>100 then status:=status+' МАТ';

 // Обновить базу
 if selfTeach then begin
  LoadDB;
  hash:=BoardHash(data[1]);
  fl:=true;
  for i:=0 to length(dbItems)-1 do
   if dbItems[i].hash=hash then begin
    dbItems[i].rate:=round(data[j].rate*1000) shl 8;
    fl:=false;
    break;
   end;
  if fl then begin
   i:=length(dbItems);
   setLength(dbItems,i+1);
   dbItems[i].hash:=hash;
   dbItems[i].rate:=round(data[j].rate*1000) shl 8;
  end;
  SaveDB;
 end;

 moveFrom:=data[j].lastTurnFrom;
 moveTo:=data[j].lastTurnTo;
 moveReady:=true;
 except
  on e:exception do ErrorMessage(e.message);
 end;

end;

procedure ThinkThread.Execute;
begin
// fillchar(cache,sizeof(cache),0);
 running:=true;
 if selfTeach then LoadDB;
 repeat
  if not MoveReady and (gameover=0) and (board.WhiteTurn xor PlayerWhite) then
   DoThink
  else
   sleep(9); // Если ход не наш - ничего не делать
 until terminated;
 running:=false;
end;

procedure LoadDB;
var
 f:file;
 i,n,h:integer;
begin
 if not fileExists('db.dat') then exit;
 try
  assign(f,'db.dat');
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

procedure SaveDB;
var
 f:file;
begin
 try
  assign(f,'db.dat');
  rewrite(f,1);
  blockwrite(f,dbItems[0],12*length(dbItems));
  close(f);
 except
  on e:exception do ErrorMessage('Error in SaveDB: '+e.message);
 end;
end;

procedure SaveLibrary;
var
 i,n:integer;
 f:file;
begin
 assign(f,'lib.dat');
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

var
 f:file;
 i,j,n:integer;
 t:text;
 v:cardinal;
 fl:boolean;
initialization
{ randomize;
 assign(t,'tab.txt');
 rewrite(t);
 for i:=0 to 15 do begin
  write(t,'          ');
  for j:=0 to 15 do begin
   v:=random(65536) shl 16+random(65536);
   write(t,'$',inttohex(v,8),',');
  end;
  writeln(t);
 end;
 close(t);}

 if fileexists('lib.dat') then begin
  try
   assign(f,'lib.dat');
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
end.
