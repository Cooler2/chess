{$A4}
unit logic;
interface
uses gamedata;
 // флаги
 //amValid=1; // только корректные ходы

 // Составляет список возможных ходов для данной фигуры (в массив moves)
 procedure GetAvailMoves(var board:TBoard;fromPos:byte;var moves:TMovesList);

 // отмечает поля, находящиеся под боем
 procedure CalcBeatable(var board:TBoard);

 procedure DoMove(var board:TBoard;from,target:byte);

 // Возвращает состояние шаха: был ли поставлен шах последним ходом
 function IsCheck(var b:TBoard):boolean;

implementation
 uses SysUtils,Apus.MyServis;

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

 procedure GetAvailMoves(var board:TBoard;fromPos:byte;var moves:TMovesList);
  var
   i,j,x,y:integer;
   v,color,color2,m,n,l:byte;
   pb:PByte;
  procedure AddMove(var pb:PByte;m:byte); inline;
   begin
    inc(pb);
    pb^:=m;
   end;
  begin
   with board do begin
    pb:=@moves;
    x:=fromPos and $F;
    y:=fromPos shr 4;
    v:=field[x,y] and $F;
    color:=field[x,y] and ColorMask;
    if v=Pawn then begin
      if color=White then begin
       // белая пешка
       if (y<7) and (field[x,y+1]=0) then AddMove(pb,fromPos+$10);
       if (y=1) and (field[x,2]=0) and (field[x,3]=0) then AddMove(pb,fromPos+$20);
       if (x>0) and (field[x-1,y+1] and ColorMask=Black) then AddMove(pb,fromPos+$10-1);
       if (x<7) and (field[x+1,y+1] and ColorMask=Black) then AddMove(pb,fromPos+$10+1);
       // взятие на проходе
       if (y=4) and (x>0) and (field[x-1,y]=PawnBlack) and
         (lastTurnFrom=fromPos+$20-1) and (lastTurnTo=fromPos-1) then AddMove(pb,fromPos+$10-1);
       if (y=4) and (x<70) and (field[x+1,y]=PawnBlack) and
         (lastTurnFrom=fromPos+$20+1) and (lastTurnTo=fromPos+1) then AddMove(pb,fromPos+$10+1);
      end else begin
       // черная пешка
       if (y>0) and (field[x,y-1]=0) then AddMove(pb,fromPos-$10);
       if (y=6) and (field[x,5]=0) and (field[x,4]=0) then AddMove(pb,fromPos-$20);
       if (x>0) and (field[x-1,y-1] and ColorMask=White) then AddMove(pb,fromPos-$10-1);
       if (x<7) and (field[x+1,y-1] and ColorMask=White) then AddMove(pb,fromPos-$10+1);
       // взятие на проходе
       if (y=3) and (x>0) and (field[x-1,y]=PawnWhite) and
         (lastTurnFrom=fromPos-$20-1) and (lastTurnTo=fromPos-1) then AddMove(pb,fromPos-$10-1);
       if (y=3) and (x<70) and (field[x+1,y]=PawnWhite) and
         (lastTurnFrom=fromPos-$20+1) and (lastTurnTo=fromPos+1) then AddMove(pb,fromPos-$10+1);
      end;
      exit;
     end;

    if v=Knight then begin
     if (x>0) and (y>1) and (field[x-1,y-2] and ColorMask<>color) then AddMove(pb,fromPos-$20-1);
     if (x<7) and (y>1) and (field[x+1,y-2] and ColorMask<>color) then AddMove(pb,fromPos-$20+1);

     if (x>0) and (y<6) and (field[x-1,y+2] and ColorMask<>color) then AddMove(pb,fromPos+$20-1);
     if (x<7) and (y<6) and (field[x+1,y+2] and ColorMask<>color) then AddMove(pb,fromPos+$20+1);

     if (x>1) and (y>0) and (field[x-2,y-1] and ColorMask<>color) then AddMove(pb,fromPos-$10-2);
     if (x>1) and (y<7) and (field[x-2,y+1] and ColorMask<>color) then AddMove(pb,fromPos+$10-2);

     if (x<6) and (y>0) and (field[x+2,y-1] and ColorMask<>color) then AddMove(pb,fromPos-$10+2);
     if (x<6) and (y<7) and (field[x+2,y+1] and ColorMask<>color) then AddMove(pb,fromPos+$10+2);
     exit;
    end;

    if v=King then begin
     // нельзя ходить на поле под боем
     if color=white then color2:=black else color2:=white;
     field[x,y]:=0;
     CalcBeatable(board);
     field[x,y]:=King+color;

     if (x>0) and (y>0) and
        (field[x-1,y-1] and ColorMask<>color) and (beatable[x-1,y-1] and color2=0) then AddMove(pb,fromPos-$10-1);
     if (x>0) and (y<7) and
        (field[x-1,y+1] and ColorMask<>color) and (beatable[x-1,y+1] and color2=0) then AddMove(pb,fromPos+$10-1);
     if (x<7) and (y>0) and
        (field[x+1,y-1] and ColorMask<>color) and (beatable[x+1,y-1] and color2=0) then AddMove(pb,fromPos-$10+1);
     if (x<7) and (y<7) and
        (field[x+1,y+1] and ColorMask<>color) and (beatable[x+1,y+1] and color2=0) then AddMove(pb,fromPos+$10+1);

     if (x>0) and (field[x-1,y] and ColorMask<>color) and (beatable[x-1,y] and color2=0) then AddMove(pb,fromPos-1);
     if (x<7) and (field[x+1,y] and ColorMask<>color) and (beatable[x+1,y] and color2=0) then AddMove(pb,fromPos+1);
     if (y>0) and (field[x,y-1] and ColorMask<>color) and (beatable[x,y-1] and color2=0) then AddMove(pb,fromPos-$10);
     if (y<7) and (field[x,y+1] and ColorMask<>color) and (beatable[x,y+1] and color2=0) then AddMove(pb,fromPos+$10);

     // Рокировка...
     if (x=4) and (y=0) and (color=White) and (rFlags and $F<3) then begin
      // Возможна рокировка хотя бы в одну сторону
      // длинная рокировка
      if (rFlags and 1=0) and (field[1,0] or field[2,0] or field[3,0]=0) and
         ((beatable[2,0] or beatable[3,0] or beatable[4,0]) and Black=0) then
           AddMove(pb,fromPos-2);
      // короткая рокировка
      if (rFlags and 2=0) and (field[5,0] or field[6,0]=0) and
         ((beatable[4,0] or beatable[5,0] or beatable[6,0]) and Black=0) then
           AddMove(pb,fromPos+2);
     end;
     if (x=4) and (y=7) and (color=Black) and (rFlags and $F0<$30) then begin
      // Возможна рокировка хотя бы в одну сторону
      // длинная рокировка
      if (rFlags and $10=0) and (field[1,7] or field[2,7] or field[3,7]=0) and
         ((beatable[2,7] or beatable[3,7] or beatable[4,7]) and White=0) then
           AddMove(pb,fromPos-2);
      // короткая рокировка
      if (rFlags and $20=0) and (field[5,7] or field[6,7]=0) and
         ((beatable[4,7] or beatable[5,7] or beatable[6,7]) and White=0) then
           AddMove(pb,fromPos+2);
     end;
     exit;
    end;

    if v in [Rook,Queen] then begin
      // ладья
      m:=fromPos;
      for i:=x+1 to 7 do begin
       if field[i,y] and ColorMask=color then break;
       m:=m+1;
       AddMove(pb,m);
       if field[i,y]<>0 then break;
      end;
      m:=fromPos;
      for i:=x-1 downto 0 do begin
       if field[i,y] and ColorMask=color then break;
       m:=m-1;
       AddMove(pb,m);
       if field[i,y]<>0 then break;
      end;
      m:=fromPos;
      for i:=y+1 to 7 do begin
       if field[x,i] and ColorMask=color then break;
       m:=m+$10;
       AddMove(pb,m);
       if field[x,i]<>0 then break;
      end;
      m:=fromPos;
      for i:=y-1 downto 0 do begin
       if field[x,i] and ColorMask=color then break;
       m:=m-$10;
       AddMove(pb,m);
       if field[x,i]<>0 then break;
      end;
     end;

    if v in [Bishop,Queen] then begin
     // Слон
     m:=fromPos;
     n:=x; l:=y;
     for i:=1 to 7 do begin
      inc(n); inc(l);
      m:=m+$10+1;
      if (n>7) or (l>7) or (field[n,l] and ColorMask=color) then break;
      AddMove(pb,m);
      if field[n,l]<>0 then break;
     end;
     m:=fromPos;
     n:=x; l:=y;
     for i:=1 to 7 do begin
      dec(n); inc(l);
      m:=m+$10-1;
      if (n>7) or (l>7) or (field[n,l] and ColorMask=color) then break;
      AddMove(pb,m);
      if field[n,l]<>0 then break;
     end;
     m:=fromPos;
     n:=x; l:=y;
     for i:=1 to 7 do begin
      inc(n); dec(l);
      m:=m-$10+1;
      if (n>7) or (l>7) or (field[n,l] and ColorMask=color) then break;
      AddMove(pb,m);
      if field[n,l]<>0 then break;
     end;
     m:=fromPos;
     n:=x; l:=y;
     for i:=1 to 7 do begin
      dec(n); dec(l);
      m:=m-$10-1;
      if (n>7) or (l>7) or (field[n,l] and ColorMask=color) then break;
      AddMove(pb,m);
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

end.
