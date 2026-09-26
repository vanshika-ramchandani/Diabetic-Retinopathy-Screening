function V = vesselConfig(CFG)
%VESSELCONFIG  Shadow CFG that retargets the shared stack onto the vessel net.
%   buildLesionNet, slidingWindowPredict and normaliseInput all read
%   CFG.patchSize / CFG.stride / CFG.nChan from the top level. Handing them a
%   copy with those three fields swapped means the vessel track reuses every
%   one of them unchanged rather than forking a parallel set of functions.
if nargin < 1, CFG = s00_config(); end
V = CFG;
V.patchSize = CFG.vesselSize;
V.stride    = CFG.vesselStride;
V.nChan     = 1;
end
