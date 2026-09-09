function G = ruleGradeICDR(masks, retinaMask)
%RULEGRADEICDR  Rule-based DR grade from lesion evidence - half of D2.
%
%   G = ruleGradeICDR(MASKS)  MASKS is HxWx5 logical from netraDetect
%                             (1 MA, 2 HE, 3 EX, 4 SE, 5 OD)
%
%   Implements the International Clinical Diabetic Retinopathy Severity Scale
%   (Wilkinson et al., Ophthalmology 2003;110:1677):
%
%     0  No DR         no visible lesions
%     1  Mild NPDR     microaneurysms only
%     2  Moderate NPDR more than MAs alone, less than severe
%     3  Severe NPDR   the 4-2-1 rule
%     4  PDR           neovascularisation / vitreous / preretinal haemorrhage
%
%   HONEST LIMITS - state these when the grade is questioned:
%     * Only the HAEMORRHAGE arm of 4-2-1 is implemented (>20 intraretinal
%       haemorrhages in each of 4 quadrants). The venous-beading and IRMA
%       arms need vessel-calibre and intraretinal-microvascular analysis that
%       this model does not perform.
%     * Level 4 is UNREACHABLE by this rule. Neovascularisation has no
%       pixel-level annotation in IDRiD or APTOS, so it was never trained.
%       G.pdrDetectable is false to make that explicit rather than implying
%       a confident "not PDR".
if nargin < 2 || isempty(retinaMask)
    retinaMask = any(masks,3) | true(size(masks,1), size(masks,2));
end

MA = masks(:,:,1); HE = masks(:,:,2); EX = masks(:,:,3); SE = masks(:,:,4);

nMA = countBlobs(MA);
nHE = countBlobs(HE);
nEX = countBlobs(EX);
nSE = countBlobs(SE);

% --- 4-2-1, haemorrhage arm ----------------------------------------------
% Quadrants are taken about the centroid of the retinal field, not the frame
% centre: fundus images are rarely centred in their own frame.
st = regionprops(retinaMask, 'Centroid');
if isempty(st)
    cy = size(HE,1)/2; cx = size(HE,2)/2;
else
    cx = st(1).Centroid(1); cy = st(1).Centroid(2);
end
qHE = zeros(1,4);
qHE(1) = countBlobs(HE(1:round(cy),        1:round(cx)));
qHE(2) = countBlobs(HE(1:round(cy),        round(cx)+1:end));
qHE(3) = countBlobs(HE(round(cy)+1:end,    1:round(cx)));
qHE(4) = countBlobs(HE(round(cy)+1:end,    round(cx)+1:end));
severeHaem = all(qHE > 20);

% --- grade ---------------------------------------------------------------
anyLesion = (nMA + nHE + nEX + nSE) > 0;
if ~anyLesion
    grade = 0; why = "no lesions detected";
elseif severeHaem
    grade = 3; why = sprintf('4-2-1 met: >20 haemorrhages in all four quadrants [%s]', ...
                             strjoin(string(qHE), ' '));
elseif nHE > 0 || nEX > 0 || nSE > 0
    grade = 2; parts = strings(0);
    if nHE>0, parts(end+1) = sprintf('%d haemorrhage(s)', nHE); end
    if nEX>0, parts(end+1) = sprintf('%d hard exudate(s)', nEX); end
    if nSE>0, parts(end+1) = sprintf('%d soft exudate(s)', nSE); end
    why = "beyond microaneurysms only: " + strjoin(parts, ', ');
else
    grade = 1; why = sprintf('%d microaneurysm(s) only', nMA);
end

G.grade          = grade;
G.referable      = grade >= 2;
G.counts         = struct('MA',nMA,'HE',nHE,'EX',nEX,'SE',nSE);
G.quadrantHaem   = qHE;
G.rule421        = severeHaem;
G.rationale      = string(why);
G.pdrDetectable  = false;   % no NV model exists - see header
G.scaleName      = ["No DR","Mild NPDR","Moderate NPDR","Severe NPDR","PDR"];
G.gradeName      = G.scaleName(grade+1);
end

function n = countBlobs(B)
if ~any(B(:)), n = 0; return; end
n = max(0, numel(regionprops(B,'Area')));
end
