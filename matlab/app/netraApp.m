function netraApp()
%NETRAAPP  NETRA screening GUI - the demo.
%
%   Built with App Designer's own uifigure/uigridlayout components, but as a
%   programmatic .m file rather than a binary .mlapp. Same widgets, same
%   look; the difference is that this one is readable in a diff and cannot be
%   silently corrupted, which matters when one person is carrying the build.
%
%   Run:  netraApp
%
%   The layout follows the pipeline: an image on the left with four views,
%   and on the right the decision chain top to bottom - quality gate, lesion
%   evidence, the two independent grades, and the dual-evidence verdict.
%   A judge should be able to read the safety argument off the screen without
%   narration.

here = fileparts(fileparts(mfilename('fullpath')));
addpath(here, fullfile(here,'lib'), fullfile(here,'m1_quality'), ...
        fullfile(here,'m2_enhance'), fullfile(here,'m4_grade'));

C = struct('navy',[0.043 0.145 0.271], 'teal',[0.055 0.486 0.525], ...
           'sage',[0.243 0.557 0.353], 'amber',[0.941 0.635 0.008], ...
           'crimson',[0.757 0.153 0.176], 'grey',[0.929 0.941 0.949], ...
           'white',[1 1 1]);

S.C = C; S.result = []; S.view = "Lesion overlay";

S.fig = uifigure('Name','NETRA - Neural Explainable Triage for Retinal Assessment', ...
                 'Position',[80 60 1360 820], 'Color',C.white);
G = uigridlayout(S.fig,[2 2]);
G.RowHeight   = {70,'1x'};
G.ColumnWidth = {'1.55x','1x'};
G.Padding = [14 14 14 14]; G.RowSpacing = 12; G.ColumnSpacing = 14;

% ---------- header -------------------------------------------------------
hdr = uipanel(G,'BackgroundColor',C.navy,'BorderType','none');
hdr.Layout.Row = 1; hdr.Layout.Column = [1 2];
hg = uigridlayout(hdr,[1 3]); hg.ColumnWidth = {'1x',170,170};
hg.Padding = [18 8 14 8]; hg.BackgroundColor = C.navy;
t = uilabel(hg,'Text','NETRA   ·   Explainable DR Screening', ...
    'FontSize',21,'FontWeight','bold','FontColor',C.white);
t.Layout.Column = 1;
S.btnLoad = uibutton(hg,'Text','Load image…','FontSize',13,'FontWeight','bold', ...
    'BackgroundColor',C.teal,'FontColor',C.white,'ButtonPushedFcn',@onLoad);
S.btnRun  = uibutton(hg,'Text','Run screening','FontSize',13,'FontWeight','bold', ...
    'BackgroundColor',C.sage,'FontColor',C.white,'Enable','off','ButtonPushedFcn',@onRun);

% ---------- left: image --------------------------------------------------
left = uipanel(G,'BackgroundColor',C.white,'BorderType','line');
left.Layout.Row = 2; left.Layout.Column = 1;
lg = uigridlayout(left,[3 1]); lg.RowHeight = {34,'1x',26};
lg.Padding = [10 10 10 10]; lg.RowSpacing = 8;

S.viewSel = uidropdown(lg, ...
    'Items',{'Original','Enhanced','Lesion overlay','Grad-CAM'}, ...
    'Value','Lesion overlay','FontSize',13,'ValueChangedFcn',@onView);
S.ax = uiaxes(lg); S.ax.XTick = []; S.ax.YTick = [];
S.ax.Box = 'on'; S.ax.Color = C.grey;
title(S.ax,'load a fundus image to begin','FontSize',12,'FontWeight','normal');
S.legend = uilabel(lg,'Text', ...
    '● microaneurysm   ● haemorrhage   ● hard exudate   ● soft exudate   ○ optic disc', ...
    'FontSize',11,'FontColor',[0.35 0.35 0.35]);

% ---------- right: the decision chain ------------------------------------
right = uipanel(G,'BackgroundColor',C.white,'BorderType','none');
right.Layout.Row = 2; right.Layout.Column = 2;
rg = uigridlayout(right,[5 1]);
rg.RowHeight = {112,118,150,150,'1x'};
rg.Padding = [0 0 0 0]; rg.RowSpacing = 10;

[S.qPanel, S.qTitle, S.qBody] = card(rg, C, '1 · QUALITY GATE', C.teal);
[S.lPanel, S.lTitle, S.lBody] = card(rg, C, '2 · LESION EVIDENCE', C.teal);
[S.gPanel, S.gTitle, S.gBody] = card(rg, C, '3 · TWO INDEPENDENT GRADES', C.teal);
[S.dPanel, S.dTitle, S.dBody] = card(rg, C, '4 · DUAL-EVIDENCE VERDICT', C.teal);

fin = uipanel(rg,'BackgroundColor',C.grey,'BorderType','none');
fg = uigridlayout(fin,[2 1]); fg.RowHeight = {'1x',34};
fg.Padding = [12 10 12 10]; fg.BackgroundColor = C.grey;
S.finalLbl = uilabel(fg,'Text','—','FontSize',17,'FontWeight','bold', ...
    'FontColor',C.navy,'WordWrap','on');
S.btnSave = uibutton(fg,'Text','Save PDF report','FontSize',12, ...
    'BackgroundColor',C.navy,'FontColor',C.white,'Enable','off','ButtonPushedFcn',@onSave);

guidata(S.fig, S);
resetCards(S.fig);

% =========================================================================
    function onLoad(~,~)
        S = guidata(S.fig);
        [f,p] = uigetfile({'*.jpg;*.jpeg;*.png;*.tif','Fundus images'}, ...
                          'Select a fundus image');
        if isequal(f,0), return; end
        S.path = fullfile(p,f);
        S.raw  = imread(S.path);
        S.result = [];
        imshow(S.raw,'Parent',S.ax);
        title(S.ax, f, 'Interpreter','none','FontSize',11);
        S.btnRun.Enable = 'on'; S.btnSave.Enable = 'off';
        S.viewSel.Value = 'Original';
        guidata(S.fig,S); resetCards(S.fig);
    end

    function onRun(~,~)
        S = guidata(S.fig);
        d = uiprogressdlg(S.fig,'Title','NETRA', ...
                'Message','running the pipeline…','Indeterminate','on');
        cleanup = onCleanup(@() close(d));
        try
            R = netraScreen(S.path, struct('verbose',false,'gradcam',true));
        catch ME
            clear cleanup;
            uialert(S.fig, ME.message, 'Pipeline error');
            return;
        end
        clear cleanup;
        S.result = R; guidata(S.fig,S);
        fillCards(S.fig);
        S = guidata(S.fig);
        if R.decisionPath == "REJECTED_AT_QUALITY_GATE"
            S.viewSel.Value = 'Original';
        else
            S.viewSel.Value = 'Lesion overlay';
        end
        S.btnSave.Enable = 'on';
        guidata(S.fig,S); onView();
    end

    function onView(~,~)
        S = guidata(S.fig); R = S.result;
        if isempty(R), return; end
        v = S.viewSel.Value;
        switch v
            case 'Original',       imshow(R.image,'Parent',S.ax);
            case 'Enhanced',       imshow(R.enhanced,'Parent',S.ax);
            case 'Lesion overlay'
                if isempty(R.masks)
                    imshow(R.image,'Parent',S.ax);
                else
                    imshow(R.overlay,'Parent',S.ax);
                end
            case 'Grad-CAM'
                imshow(R.image,'Parent',S.ax);
                if ~isempty(R.gradcam)
                    hold(S.ax,'on');
                    h = imagesc(S.ax, R.gradcam);
                    set(h,'AlphaData',0.42);
                    colormap(S.ax,'jet'); hold(S.ax,'off');
                end
        end
        title(S.ax, v, 'FontSize',11);
    end

    function onSave(~,~)
        S = guidata(S.fig); R = S.result;
        if isempty(R), return; end
        [f,p] = uiputfile('netra_report.pdf','Save report');
        if isequal(f,0), return; end
        try
            writeReport(R, fullfile(p,f), S.C);
            uialert(S.fig, sprintf('Saved %s', fullfile(p,f)), 'Report saved', 'Icon','success');
        catch ME
            uialert(S.fig, ME.message, 'Could not save report');
        end
    end

    function resetCards(figh)
        S = guidata(figh);
        for h = [S.qBody S.lBody S.gBody S.dBody]
            h.Text = '—'; h.FontColor = [0.45 0.45 0.45];
        end
        S.finalLbl.Text = '—';
        for h = [S.qPanel S.lPanel S.gPanel S.dPanel]
            h.BackgroundColor = S.C.white;
        end
        guidata(figh,S);
    end

    function fillCards(figh)
        S = guidata(figh); R = S.result; C = S.C;

        % ---- 1 quality --------------------------------------------------
        q = R.quality;
        switch string(q.decision)
            case "PASS",    qc = C.sage;
            case "ENHANCE", qc = C.amber;
            case "REJECT",  qc = C.crimson;
            otherwise,      qc = [0.45 0.45 0.45];
        end
        S.qTitle.BackgroundColor = qc;
        txt = sprintf('%s   ·   gradeability %s/100', q.decision, num2str(q.score));
        if ~isempty(q.reasons)
            txt = [txt newline '• ' strjoin(cellstr(string(q.reasons)), [newline '• '])];
        end
        if q.decision == "REJECT"
            txt = [txt newline newline 'ACTION: ' char(q.instruction)];
        end
        S.qBody.Text = txt; S.qBody.FontColor = C.navy;

        if R.decisionPath == "REJECTED_AT_QUALITY_GATE"
            S.lBody.Text = 'not computed — image rejected before grading';
            S.gBody.Text = 'not computed — NETRA does not grade what it cannot read';
            S.dBody.Text = 'not computed';
            S.dTitle.BackgroundColor = C.crimson;
            S.finalLbl.Text = char(R.reportLine);
            S.finalLbl.FontColor = C.crimson;
            guidata(figh,S); return;
        end

        % ---- 2 lesions --------------------------------------------------
        c = R.lesionCounts;
        S.lBody.Text = sprintf(['microaneurysms   %d\nhaemorrhages     %d\n' ...
            'hard exudates    %d\nsoft exudates    %d\nquadrant haem.   [%s]'], ...
            c.MA, c.HE, c.EX, c.SE, strjoin(string(R.ruleGrade.quadrantHaem),' '));
        S.lBody.FontColor = C.navy;

        % ---- 3 the two grades -------------------------------------------
        if R.cnnGrade.available
            S.gBody.Text = sprintf(['CNN (ResNet-18)   grade %d   conf %.2f\n' ...
                'Lesion rules      grade %d\n%s'], ...
                R.cnnGrade.grade, R.cnnGrade.confidence, ...
                R.ruleGrade.grade, char(R.ruleGrade.rationale));
        else
            S.gBody.Text = sprintf(['CNN               unavailable\n' ...
                'Lesion rules      grade %d\n%s'], ...
                R.ruleGrade.grade, char(R.ruleGrade.rationale));
        end
        S.gBody.FontColor = C.navy;

        % ---- 4 dual evidence --------------------------------------------
        if isempty(R.dual)
            S.dTitle.BackgroundColor = C.amber;
            S.dBody.Text = 'lesion rules only — CNN grader not loaded';
        else
            if R.dual.agree
                S.dTitle.BackgroundColor = C.sage;
            else
                S.dTitle.BackgroundColor = C.crimson;
            end
            S.dBody.Text = sprintf('%s\n%s\n\n• %s', R.dual.decision, R.dual.action, ...
                strjoin(R.dual.reasons, [newline '• ']));
        end
        S.dBody.FontColor = C.navy;

        S.finalLbl.Text = char(R.reportLine);
        if R.referable, S.finalLbl.FontColor = C.crimson;
        else,           S.finalLbl.FontColor = C.sage; end
        guidata(figh,S);
    end
end

% =========================================================================
function [p, titleLbl, bodyLbl] = card(parent, C, heading, headColor)
p = uipanel(parent,'BackgroundColor',C.white,'BorderType','line');
g = uigridlayout(p,[2 1]); g.RowHeight = {24,'1x'};
g.Padding = [0 0 0 0]; g.RowSpacing = 0;
titleLbl = uilabel(g,'Text',['  ' heading],'FontSize',11.5,'FontWeight','bold', ...
    'FontColor',C.white,'BackgroundColor',headColor);
bodyLbl = uilabel(g,'Text','—','FontSize',12,'WordWrap','on', ...
    'VerticalAlignment','top','FontName','Consolas');
bodyLbl.Layout.Row = 2;
end

function writeReport(R, outPath, C)
%WRITEREPORT  One-page PDF screening report.
f = figure('Visible','off','Units','inches','Position',[0 0 8.27 11.69], ...
           'PaperUnits','inches','PaperSize',[8.27 11.69], ...
           'PaperPosition',[0 0 8.27 11.69],'Color','w');

annotation(f,'textbox',[0.06 0.985 0.9 0.0], 'String','NETRA — DR screening report', ...
    'FontSize',17,'FontWeight','bold','Color',C.navy,'EdgeColor','none', ...
    'VerticalAlignment','top');
annotation(f,'textbox',[0.06 0.955 0.9 0.0], ...
    'String',sprintf('%s      generated %s', R.imagePath, datestr(now,'yyyy-mm-dd HH:MM')), ...
    'FontSize',9,'Color',[0.4 0.4 0.4],'EdgeColor','none','Interpreter','none', ...
    'VerticalAlignment','top');

ax1 = axes(f,'Position',[0.06 0.60 0.42 0.31]); imshow(R.image,'Parent',ax1);
title(ax1,'capture','FontSize',10);
ax2 = axes(f,'Position',[0.52 0.60 0.42 0.31]);
if ~isempty(R.masks), imshow(R.overlay,'Parent',ax2); title(ax2,'lesion evidence','FontSize',10);
else, imshow(R.image,'Parent',ax2); title(ax2,'not graded','FontSize',10); end

lines = reportLines(R);
annotation(f,'textbox',[0.06 0.55 0.88 0.0],'String',lines, ...
    'FontSize',10.5,'FontName','Consolas','EdgeColor',[0.85 0.85 0.85], ...
    'BackgroundColor',[0.97 0.97 0.97],'Margin',10,'VerticalAlignment','top', ...
    'Interpreter','none','FitBoxToText','on');

annotation(f,'textbox',[0.06 0.05 0.88 0.03], ...
    'String',['Screening aid only. Not a diagnosis. Every REFERABLE or ESCALATED ' ...
              'result requires ophthalmologist review.'], ...
    'FontSize',8.5,'FontAngle','italic','Color',[0.45 0.45 0.45],'EdgeColor','none');

exportgraphics(f, outPath, 'ContentType','vector');
close(f);
end

function L = reportLines(R)
L = {};
L{end+1} = sprintf('QUALITY GATE     %s  (score %s/100)', R.quality.decision, num2str(R.quality.score));
for i = 1:numel(R.quality.reasons)
    L{end+1} = sprintf('                 - %s', string(R.quality.reasons{i})); %#ok<AGROW>
end
if R.decisionPath == "REJECTED_AT_QUALITY_GATE"
    L{end+1} = '';
    L{end+1} = sprintf('ACTION           %s', R.quality.instruction);
    L{end+1} = 'No grade was produced. This is intended behaviour.';
    return;
end
c = R.lesionCounts;
L{end+1} = '';
L{end+1} = sprintf('LESIONS          MA %d | HE %d | EX %d | SE %d', c.MA, c.HE, c.EX, c.SE);
L{end+1} = sprintf('RULE GRADE       %d  (%s)', R.ruleGrade.grade, R.ruleGrade.gradeName);
L{end+1} = sprintf('                 %s', R.ruleGrade.rationale);
if R.cnnGrade.available
    L{end+1} = sprintf('CNN GRADE        %d  (confidence %.2f)', R.cnnGrade.grade, R.cnnGrade.confidence);
end
if ~isempty(R.dual)
    L{end+1} = '';
    L{end+1} = sprintf('DUAL EVIDENCE    %s', R.dual.decision);
    for i = 1:numel(R.dual.reasons)
        L{end+1} = sprintf('                 - %s', R.dual.reasons(i)); %#ok<AGROW>
    end
end
L{end+1} = '';
L{end+1} = sprintf('RESULT           %s', R.reportLine);
L{end+1} = 'Neovascularisation is not assessed by this model (no training labels).';
end
