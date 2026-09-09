function lightAxes(f)
%LIGHTAXES  Force every axes in F to light colours before export.
%   theme() alone does not always repaint axes created before it was called,
%   so this is applied immediately before exportgraphics.
set(f,'Color','w');
ax = findall(f,'Type','axes');
for a = ax(:)'
    set(a,'Color','w','XColor',[0.15 0.15 0.15],'YColor',[0.15 0.15 0.15], ...
          'GridColor',[0.75 0.75 0.75]);
    t = get(a,'Title');  if ~isempty(t), set(t,'Color',[0.04 0.14 0.27]); end
    x = get(a,'XLabel'); if ~isempty(x), set(x,'Color',[0.15 0.15 0.15]); end
    y = get(a,'YLabel'); if ~isempty(y), set(y,'Color',[0.15 0.15 0.15]); end
end
lg = findall(f,'Type','legend');
for l = lg(:)', set(l,'Color','w','TextColor',[0.15 0.15 0.15]); end
sg = findall(f,'Type','subplottext');
for s = sg(:)', set(s,'Color',[0.04 0.14 0.27]); end
end
