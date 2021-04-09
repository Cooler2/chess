{$SETPEFLAGS $20} // Allow 4GB memory space for 32-bit process
program chess;

uses
  Forms,
  main in 'main.pas' {MainForm},
  logic in 'logic.pas',
  TreeView in 'TreeView.pas' {TreeWnd},
  gamedata in 'gamedata.pas',
  AI in 'AI.pas',
  cache in 'cache.pas',
  SelfLearn in 'SelfLearn.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.CreateForm(TMainForm, MainForm);
  Application.CreateForm(TTreeWnd, TreeWnd);
  Application.Run;
end.
