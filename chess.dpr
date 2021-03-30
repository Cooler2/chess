program chess;

uses
  Forms,
  main in 'main.pas' {MainForm},
  logic in 'logic.pas',
  TreeView in 'TreeView.pas' {TreeWnd},
  gamedata in 'gamedata.pas',
  AI in 'AI.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.CreateForm(TMainForm, MainForm);
  Application.CreateForm(TTreeWnd, TreeWnd);
  Application.Run;
end.
