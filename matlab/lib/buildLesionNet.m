function net = buildLesionNet(baseNet, CFG)
%BUILDLESIONNET  ResNet-18 encoder + U-Net decoder, 512x512x3 -> 512x512x5 sigmoid.
%   BASENET is a resnet18-shaped dlnetwork: either fresh ImageNet weights or the
%   APTOS-finetuned encoder from s03. Building directly on it means there is no
%   weight "transplant" step to get wrong.
%
%   Multi-label sigmoid, not softmax: lesions co-occur at the same pixel.
%
%   U-Net rather than deeplabv3plus (also available) because microaneurysms are
%   ~10 px wide at native resolution and a stride-16 output cannot recover them.

if nargin < 2, CFG = s00_config(); end
ps = CFG.patchSize;
net = baseNet;

% ---- strip the classification head (robust to how s03 renamed it) -------
isHead = arrayfun(@(L) isa(L,'nnet.cnn.layer.GlobalAveragePooling2DLayer') || ...
                       isa(L,'nnet.cnn.layer.FullyConnectedLayer')        || ...
                       isa(L,'nnet.cnn.layer.SoftmaxLayer'), net.Layers);
if any(isHead)
    net = removeLayers(net, {net.Layers(isHead).Name});
end

% ---- resize the input (resnet18 ships as 224; we feed 512 patches) ------
inName = net.InputNames{1};
net = replaceLayer(net, inName, ...
        imageInputLayer([ps ps 3], Name=inName, Normalization='none'));

% ---- decoder ------------------------------------------------------------
% taps verified against this exact network at 512 input:
%   conv1_relu 256x256x64 | res2b_relu 128x128x64 | res3b_relu 64x64x128
%   res4b_relu 32x32x256  | res5b_relu 16x16x512  (bottleneck)
skips   = {'res4b_relu','res3b_relu','res2b_relu','conv1_relu'};
upFilt  = [256 128 64 64];
outFilt = [256 128 64 32];
src     = 'res5b_relu';

for k = 1:4
    p = sprintf('dec%d_',k);
    blk = [
        transposedConv2dLayer(2, upFilt(k), Stride=2, Name=[p 'up'])
        concatenationLayer(3, 2, Name=[p 'cat'])
        convolution2dLayer(3, outFilt(k), Padding='same', Name=[p 'conv1'])
        batchNormalizationLayer(Name=[p 'bn1'])
        reluLayer(Name=[p 'relu1'])
        convolution2dLayer(3, outFilt(k), Padding='same', Name=[p 'conv2'])
        batchNormalizationLayer(Name=[p 'bn2'])
        reluLayer(Name=[p 'relu2'])];
    net = addLayers(net, blk);
    net = connectLayers(net, src,      [p 'up']);
    net = connectLayers(net, skips{k}, [p 'cat/in2']);
    src = [p 'relu2'];
end

% ---- final 2x up to full patch resolution, then per-lesion sigmoid ------
head = [
    transposedConv2dLayer(2, 32, Stride=2, Name='out_up')
    convolution2dLayer(3, 32, Padding='same', Name='out_conv')
    batchNormalizationLayer(Name='out_bn')
    reluLayer(Name='out_relu')
    convolution2dLayer(1, CFG.nChan, Padding='same', Name='out_logits')
    sigmoidLayer(Name='out_prob')];
net = addLayers(net, head);
net = connectLayers(net, src, 'out_up');

net = initialize(net);   % initialises new layers only; encoder weights survive
end
