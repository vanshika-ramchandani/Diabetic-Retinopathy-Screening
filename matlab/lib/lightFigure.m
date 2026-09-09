function f = lightFigure(varargin)
%LIGHTFIGURE  An invisible figure forced to the light theme.
%   R2026a renders figures in the desktop's dark theme by default, which
%   exports charcoal panels into a white presentation. Every deck figure must
%   go through here, not through bare figure().
f = figure('Visible','off','Color','w', varargin{:});
try
    theme(f,'light');          % R2025a+
catch
    set(f,'Color','w');        % older releases: nothing to undo
end
end
