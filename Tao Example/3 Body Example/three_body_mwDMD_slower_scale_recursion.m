clear; close all; clc

% addpath('altmany-export_fig-9ac0917');
addpath(genpath('../optdmd-master'));

colorlist = {'k','r','b','g','c','m'};

load('mwDMD_sep_recon_slow_recursion.mat');
x = xr_sep{1};
TimeSpan = tspan;

% r = size(x,1); %rank to fit w/ optdmd
r = 4;

imode = 1; %parameter for optdmd code
%  imode = 1, fit full data, slower
%  imode = 2, fit data projected onto first r POD modes
%      or columns of varargin{2} (should be at least r
%      columns in varargin{2})

nComponents = 2; %number of distinct time scales present

global_SVD = 1; %use global SVD modes for each DMD rather than individual SVD on each window

if global_SVD == 1
    [u,~,v] = svd(x,'econ');
    u = u(:,1:r); %just first r modes
    v = v(:,1:r);
end

initialize_artificially = 0; %this is required for use_last_freq OR use_median_freqs
if initialize_artificially
    use_last_freq = 0; 
    use_median_freqs = 1; %mutually exclusive w/ use_last_freq
else
    use_last_freq = 0;
    use_median_freqs = 0;
end

if use_median_freqs == 1
    load('km_centroids_slower_recursion.mat');
    freq_meds = repelem(sqrt(km_centroids),r/nComponents);
end

wSteps = 7200;
% wSteps = 36000;
nSplit = floor(length(tspan)/wSteps); %number of windows if they were non-overlapping
% nSteps = wSteps * nSplit;
nSteps = length(tspan);
% nSteps = wSteps + 80*40;
nVars = size(x,1);
thresh_pct = 1;

% stepSize = wSteps/10;
stepSize = 80;

nSlide = floor((nSteps-wSteps)/stepSize);

save('mwDMD_params_slower_recursion.mat','r','nComponents','initialize_artificially','use_last_freq','use_median_freqs','wSteps','nSplit','nSteps','nVars','thresh_pct','stepSize','nSlide');

% %% Detrend
% 
% x_trended = x;
% 
T=[tspan(1:nSteps); ones(size(tspan(1:nSteps)))];
detrend_coeff = zeros(nVars,2);


% detrend_coeff = x * pinv(T);
% x = x - detrend_coeff*T;




%% execute optDMD

corner_sharpness = 16; %higher = sharper corners
lv_kern = tanh(corner_sharpness*(1:wSteps)/wSteps) - tanh(corner_sharpness*((1:wSteps)-wSteps)/wSteps) - 1;

mr_res = cell(nSlide,1);
for k = 1:nSlide
    sampleStart = stepSize*(k-1) + 1;
    sampleSteps = sampleStart : sampleStart + wSteps - 1;
    xSample = x(:,sampleSteps);
    tSample = TimeSpan(sampleSteps);

    mr_res{k}.x = xSample;
    mr_res{k}.t = tSample;
    
    c = mean(xSample,2); %subtract off mean before rounding corners
    xSample = xSample - repmat(c,1,size(xSample,2));
    
    xSample = xSample.*repmat(lv_kern,nVars,1); %round off corners
    
    t_start = tSample(1);
    tSample = tSample - t_start;
    if global_SVD == 0
        [u,~,~] = svd(xSample,'econ');
        u = u(:,1:r);
    end
    if (exist('e_init','var')) && (initialize_artificially == 1)
        try
            [w, e, b] = optdmd(xSample,tSample,r,imode,[],e_init,u);
        catch ME
            run('setup.m');
            [w, e, b] = optdmd(xSample,tSample,r,imode,[],e_init,u);
        end
            
    else
        try
            [w, e, b] = optdmd(xSample,tSample,r,imode,[],[],u);
        catch ME
            run('setup.m');
            [w, e, b] = optdmd(xSample,tSample,r,imode,[],[],u);
        end
    end
    if use_last_freq == 1
        e_init = e;
    end
    if use_median_freqs == 1
        [eSq, eInd] = sort(e.*conj(e)); %match order to that of freq_meds
        freq_angs = angle(e(eInd));
        e_init = exp(sqrt(-1)*freq_angs) .* freq_meds;
    end
    mr_res{k}.w = w;
    mr_res{k}.Omega = e;
    mr_res{k}.b = b;
    mr_res{k}.c = c;
    mr_res{k}.t_start = t_start;
end


%% Cluster Frequencies
close all;
if exist('mr_res','var') == 0
    try
        load('mwDMD_mr_res_slower_recursion_i2.mat');
    catch ME
        load('mwDMD_mr_res_slower_recursion.mat');
    end
end

% nBins = 64;



all_om = [];
all_om_grouped = [];
for k = 1:nSlide
    try
        Omega = mr_res{k}.Omega;
    catch ME
        disp(['Error on k = ' num2str(k)]);
        continue
    end
    all_om = [all_om; Omega];
    [~,imSortInd] = sort(imag(Omega));
    all_om_grouped = [all_om_grouped; Omega(imSortInd).'];
end

all_om_sq = conj(all_om) .* all_om;
all_om_sq = sort(all_om_sq);
all_om_sq_thresh = all_om_sq(floor(thresh_pct*length(all_om_sq)));
all_om_sq = all_om_sq(1:floor(thresh_pct*length(all_om_sq)));


[~, km_centroids] = kmeans(all_om_sq,nComponents,'Distance','cityblock','Replicates',5);

[km_centroids,sortInd] = sort(km_centroids);

if use_median_freqs == 0
    save('km_centroids_slower_recursion.mat','km_centroids');
end

for k = 1:nSlide
    try
        omega = mr_res{k}.Omega;
    catch ME
        continue
    end
    om_sq = omega.*conj(omega);

    om_sq_dists  = (repmat(km_centroids.',r,1) - repmat(om_sq,1,nComponents)).^2;
    [~,om_class] = min(om_sq_dists,[],2);

    mr_res{k}.om_class = om_class;
end

%% Save mr_res

if use_median_freqs == 0
    save('mwDMD_mr_res_slower_recursion.mat', 'mr_res', '-v7.3');
else
    save('mwDMD_mr_res_slower_recursion_i2.mat', 'mr_res', '-v7.3');
end


%% Plot MultiRes Results
close all;
if exist('mr_res','var') == 0
    try
        load('mwDMD_mr_res_slower_recursion_i2.mat');
    catch ME
        load('mwDMD_mr_res_slower_recursion.mat');
    end
end

export_result = 0;
logScale = 0;

% figure('units','pixels','Position',[0 0 1366 2*768])

% plotDims = [3 4]; %rows, columns of plot grid on screen at a given time
% plotDims = [1 4]; %rows, columns of plot grid on screen at a given time
    
x_PoT = x(:,1:nSteps);
t_PoT = TimeSpan(1:nSteps);
%res_list: [pn, level #, nSplit, sampleSteps/nSplit]

dupShift = 0; %multiplier to shift duplicate values so they can be visually distinguished

nBins = 64;

figure('units','pixels','Position',[100 100 1200 400])
%     j = res_list(q,2);
%     pn = res_list(q,1);
%     nSplit = 2^(j-1);

%     om_spec = zeros(nVars,nSteps);
all_om = [];


for k = 1:nSlide
    Omega = mr_res{k}.Omega;
    all_om = [all_om; Omega];
end
all_om_sq = sort(all_om .* conj(all_om));
thresh_om_sq = all_om_sq(floor(thresh_pct*length(all_om_sq)));
all_om_sq = all_om_sq(1:floor(thresh_pct*length(all_om_sq)));
subplot(2,2,[1 3]);
om_hist = histogram(all_om_sq,nBins);
mesh_pad = 10;
bin_mesh = om_hist.BinEdges(1)-mesh_pad:0.5:om_hist.BinEdges(end)+mesh_pad;
xlabel('|\omega|^2');
ylabel('Count');
title('|\omega|^2 Spectrum & k-Means Centroids');
hold on

yl = ylim;
for c = 1:nComponents
    plot([km_centroids(c), km_centroids(c)], yl,'Color',colorlist{c},'LineWidth',2)
end
xr = zeros(size(x(:,1:nSteps))); %reconstructed time series
xn = zeros(nSteps,1); %count # of windows contributing to each step
for k = 1:nSlide
    w = mr_res{k}.w;
    b = mr_res{k}.b;
    Omega = mr_res{k}.Omega;
    om_class = mr_res{k}.om_class;
    t = mr_res{k}.t;
    c = mr_res{k}.c;
    t_start = mr_res{k}.t_start;
    tShift = t-t(1); %compute each segment of xr starting at "t = 0"
%     t_nudge = 5;
    xr_window = w*diag(b)*exp(Omega*(t-t_start)) + c;
    xr(:,(k-1)*stepSize+1:(k-1)*stepSize+wSteps) = xr(:,(k-1)*stepSize+1:(k-1)*stepSize+wSteps) + xr_window;
    xn((k-1)*stepSize+1:(k-1)*stepSize+wSteps) = xn((k-1)*stepSize+1:(k-1)*stepSize+wSteps) + 1;

    % Plot |omega|^2 spectrum
    om_sq = conj(Omega).*Omega;

    om_class = om_class(om_sq <= thresh_om_sq);
    om_sq = om_sq(om_sq <= thresh_om_sq); %threshold to remove outliers
    for oi = 1:length(om_sq)
        for oj = oi:length(om_sq)
            if (abs(om_sq(oi)-om_sq(oj))/((om_sq(oi)+om_sq(oj))/2)) <= dupShift && (oi ~= oj)
                om_sq(oi) = om_sq(oi)*(1-dupShift);
                om_sq(oj) = om_sq(oj)*(1+dupShift);
            end
        end
    end
%     om_window_spec = repmat(om_sq, 1, wSteps);
%         om_spec(:,stepSize*(k-1) + 1 : stepSize*(k-1) + wSteps) = om_window_spec;

    subplot(2,2,2);

    for g = 1:nComponents
        om_window_spec_cat = om_sq(om_class == g,:);
        if isempty(om_window_spec_cat) == 1
            continue
        end
        if logScale == 1
            for f = 1:length(om_window_spec_cat)
                semilogy(mean(t),om_window_spec_cat(f),'.','Color',colorlist{g},'LineWidth',1,'MarkerSize',10);
            end
        else
            for f = 1:length(om_window_spec_cat)
                plot(mean(t),om_window_spec_cat,'.','Color',colorlist{g},'LineWidth',1,'MarkerSize',10);
            end
        end
        hold on
    end
    title('|\omega|^2 Spectra (Moving Window)');
end

subplot(2,2,4);
plot(t_PoT,real(x_PoT),'k-','LineWidth',1.5) %plot ground truth
xlabel('t')
ylabel('Measurement Data')
xMax = max(max(abs(x_PoT)));
ylim(1.5*[-xMax, xMax]);
hold on

xr = xr./repmat(xn.',nVars,1); %weight xr so all steps are on equal footing
plot(t_PoT,real(xr),'b-','LineWidth',1.5) %plot averaged reconstruction
title('Input (Black); DMD Recon. (Blue)');


if export_result == 1
    if lv == 1
        export_fig 'manyres_opt' '-pdf';
%             print(gcf, '-dpdf', 'manyres_opt.pdf'); 
    else
        export_fig 'manyres_opt' '-pdf' '-append';
%             print(gcf, '-dpdf', 'manyres_opt.pdf', '-append'); 
    end
    close(gcf);
end

%% Link Consecutive Modes
if exist('mr_res','var') == 0
    try
        load('mwDMD_mr_res_slower_recursion_i2.mat');
    catch ME
        load('mwDMD_mr_res_slower_recursion.mat');
    end
end

allModes = zeros(nSlide,nVars,r);
allFreqs = zeros(nSlide,r);
catList = flipud(perms(1:r));
modeCats = zeros(nSlide,r);
modeCats(1,:) = 1:r; %label using order of 1st modes
allModes(1,:,:) = mr_res{1}.w;

allFreqs(1,:) = mr_res{1}.Omega;
[~,catsAsc] = sort(mr_res{1}.Omega.*conj(mr_res{1}.Omega)); %category labels in ascending frequency order

distThresh = 0;
% distThresh = 0.11; %if more than one mode is within this distance then match using derivative
% minDists = zeros(nSlide-1,1);
permDistsHist = zeros(size(catList,1),nSlide-1);
for k = 2:nSlide
    w_old = squeeze(allModes(k-1,:,:));
    w = mr_res{k}.w;
    permDists = zeros(size(catList,1),1);
    for np = 1:size(catList,1)
        permDists(np) = norm(w(:,catList(np,:))-w_old);
    end
    permDistsHist(:,k-1) = sort(permDists);
%     minDists(k-1) = min(permDists);
    if nnz(permDists <= distThresh) >= 1
        if k == 2 %can't compute derivative 1 step back, so skip it
            [~,minCat] = min(permDists);
            continue;
        end
        w_older = squeeze(allModes(k-2,:,:));
        [~,minInds] = sort(permDists); %minInds(1) and minInds(2) point to 2 lowest distances
        
        wPrime = w - w_old;
        wPrime_old = w_old - w_older;
        
        for j = 1:size(wPrime,2)
            wPrime(:,j) = wPrime(:,j)/norm(wPrime(:,j));
            wPrime_old(:,j) = wPrime_old(:,j)/norm(wPrime_old(:,j));
        end
        
        derivDists = zeros(2,1);
        for np = 1:length(derivDists)
            derivDists(np) = norm(wPrime(:,catList(minInds(np),:))-wPrime_old);
        end
        
        [~,minDerInd] = min(derivDists);
        derivDistsSort = sort(derivDists);
        permDistsSort= sort(permDists);
        disp(['Derivative-Matching on k = ' num2str(k)])
        if (derivDistsSort(2)-derivDistsSort(1)) > (permDistsSort(2) - permDistsSort(1))
            minCat = minInds(minDerInd);
            [~,minCatNaive] = min(permDists);
            if minCat ~= minCatNaive
                disp('Naive result was wrong!')
            end
        else
            [~,minCat] = min(permDists);
            disp('Naive result trumps derivative match')
        end
        
    else
        [~,minCat] = min(permDists);
    end
    modeCats(k,:) = catList(minCat,:);
    allModes(k,:,:) = w(:,catList(minCat,:));
    allFreqs(k,:) = mr_res{k}.Omega(catList(minCat,:));
end
meanFreqsSq = sum(allFreqs.*conj(allFreqs),1)/nSlide;


if use_median_freqs == 0
    save('mwDMD_allModes_slower_recursion.mat','allModes','allFreqs');
else
    save('mwDMD_allModes_slower_recursion_i2.mat','allModes','allFreqs');    
end

%% Second derivative of mode coordinates
sd_norms = zeros(r,size(allModes,1)-2);
for j = 1:r
    tsPP = allModes(1:end-2,:,j) + allModes(3:end,:,j) - 2*allModes(2:end-1,:,j);
    sd_norms(j,:) = vecnorm(tsPP.');
end
sd_norms = vecnorm(sd_norms).';

sd_thresh = 0.1; %threshold above which to try different permutations to reduce 2nd deriv
                 %can be set to 0 to just check every step
ppOverrideRatio = 0.7; %apply new permutation if 2nd deriv is reduced by at least this factor
   
% figure
% plot(sd_norms)
% hold on
% plot (1:length(sd_norms),sd_thresh*ones(length(sd_norms),1))

for k = 2:nSlide-1
    thisData = allModes(k-1:k+1,:,:);
    tdPP = squeeze(thisData(1,:,:) + thisData(3,:,:) - 2*thisData(2,:,:));
    if norm(tdPP) < sd_thresh
        continue;
    end
    permDists = zeros(size(catList,1),1);
    permData = zeros(size(thisData));
    for np = 1:size(catList,1)
        %hold k-1 configuration constant, permute k and k+1 registers
        permData(1,:,:) = thisData(1,:,:);
        permData(2:3,:,:) = thisData(2:3,:,catList(np,:));
        permPP = squeeze(permData(1,:,:) + permData(3,:,:) - 2*permData(2,:,:));
        permDists(np) = norm(permPP);
        if permDists(np) <= ppOverrideRatio * norm(tdPP)
            newCat = catList(np,:);
            allModes(k:end,:,:) = allModes(k:end,:,newCat);
            modeCats(k,:) = modeCats(k,newCat);
            disp(['2nd Deriv. Perm. Override: k = ' num2str(k)]);
        end
    end
end

if use_median_freqs == 0
    save('mwDMD_allModes_slower_recursion.mat','allModes','allFreqs');
else
    save('mwDMD_allModes_slower_recursion_i2.mat','allModes','allFreqs');    
end

% %% Visualize Modes
% 
% figure('units','pixels','Position',[0 0 1366 768])
% 
% w = squeeze(allModes(1,:,:));
% wPlots = cell(r,r);
% wTrails = cell(r,r);
% trailLength = 1000; %in window steps
% % Plot time series
% subplot(3,3,7:9)
% plot(TimeSpan(1:nSteps),x(:,1:nSteps),'LineWidth',1.5)
% xlim([TimeSpan(1) TimeSpan(nSteps)])
% hold on
% lBound = plot([mr_res{1}.t(1) mr_res{1}.t(1)],ylim,'r-','LineWidth',2);
% hold on
% rBound = plot([mr_res{1}.t(end) mr_res{1}.t(end)],ylim,'r-','LineWidth',2);
% hold on
% % Plot 1st frame
% for dim = 1:r
%     subplot(3,3,dim)
%     wi = w(dim,:);
%     for j = 1:r
%         wPlots{dim,j} = plot(real(wi(j)),imag(wi(j)),'o','Color',colorlist{j},'MarkerSize',7);
%         hold on
%         wTrails{dim,j} = plot(real(wi(j)),imag(wi(j)),'-','Color',colorlist{j},'LineWidth',0.1);
%         hold on
%         wTrails{dim,j}.Color(4) = 0.3; % 50% opacity
%     end
%     title(['Proj. Modes into Dimension ' num2str(dim)])
%     axis equal
%     xlim([-1 1])
%     ylim([-1 1])
%     xlabel('Real');
%     ylabel('Imag');
%     plot(xlim,[0 0],'k:')
%     hold on
%     plot([0 0],ylim,'k:')
%     hold off
% end
% legend([wPlots{r,catsAsc(1)},wPlots{r,catsAsc(2)},wPlots{r,catsAsc(3)},wPlots{r,catsAsc(4)}],{'LF Mode 1','LF Mode 2','HF Mode 1','HF Mode 2'},'Position',[0.93 0.65 0.05 0.2])
% %Plot subsequent frames
% for k = 2:nSlide
%     w = squeeze(allModes(k,:,:));
%     for dim = 1:r
% %         subplot(4,4,dim)
%         wi = w(dim,:);
%         for j = 1:r
%             wPlots{dim,j}.XData = real(wi(j));
%             wPlots{dim,j}.YData = imag(wi(j));
%             if k > trailLength
%                 wTrails{dim,j}.XData = [wTrails{dim,j}.XData(2:end) real(wi(j))];
%                 wTrails{dim,j}.YData = [wTrails{dim,j}.YData(2:end) imag(wi(j))];
%             else
%                 wTrails{dim,j}.XData = [wTrails{dim,j}.XData real(wi(j))];
%                 wTrails{dim,j}.YData = [wTrails{dim,j}.YData imag(wi(j))];
%             end
%         end
%     end
%     lBound.XData = [mr_res{k}.t(1) mr_res{k}.t(1)];
%     rBound.XData = [mr_res{k}.t(end) mr_res{k}.t(end)];
%     pause(0.05)
% end
% 
% %% Times series of mode coordinates
% figure('units','pixels','Position',[100 100 1366 768])
% for j = 1:r
%     subplot(r,2,2*j-1)
%     plot(real(allModes(:,:,j)))
%     title(['Re[w_' num2str(j) ']'])
% %     legend('a','b','r','\theta')
%     if j == r
%         xlabel('Window #')
%     end
%     subplot(r,2,2*j)
%     plot(imag(allModes(:,:,j)))
%     title(['Im[w_' num2str(j) ']'])
% %     legend('a','b','r','\theta')
%     if j == r
%         xlabel('Window #')
%     end
% end
% 
% %% Times series of modes in polar coordinates
% figure('units','pixels','Position',[100 100 1366 768])
% for j = 1:r
%     cMode = squeeze(allModes(:,j,:));
%     rMode = abs(cMode);
%     thMode = unwrap(angle(cMode));
%     subplot(r,2,2*j-1)
%     plot(rMode)
%     title(['Magnitudes of Modes in Dim. ' num2str(j)])
%     legend({'HF','HF','LF','LF'})
% %     legend('a','b','r','\theta')
%     if j == r
%         xlabel('Window #')
%     end
%     subplot(r,2,2*j)
%     plot(thMode)
%     title(['Angles of Modes in Dim. ' num2str(j)])
%     legend({'HF','HF','LF','LF'})
% %     legend('a','b','r','\theta')
%     if j == r
%         xlabel('Window #')
%     end
% end
% 
% %% Show how modes are reflections of one another
% figure('units','pixels','Position',[100 100 1366 768])
% subplot(2,2,1)
% plot(real(allModes(:,:,1) - conj(allModes(:,:,2))))
% title('Re[w_1 - w_2^*]')
% subplot(2,2,2)
% plot(imag(allModes(:,:,1) - conj(allModes(:,:,2))))
% title('Im[w_1 - w_2^*]')
% 
% subplot(2,2,3)
% plot(real(allModes(:,:,3) - conj(allModes(:,:,4))))
% title('Re[w_3 - w_4^*]')
% subplot(2,2,4)
% plot(imag(allModes(:,:,3) - conj(allModes(:,:,4))))
% title('Im[w_3 - w_4^*]')
% 
% %% Output mode time series data
% t_step = (tspan(2)-tspan(1))*stepSize; %time per window sliding step
% start_steps = 100; %chop off from beginning to get rid of initial transients
% % good_winds = [start_steps:626, 644:nSlide]; %manually excise outliers from DMD error
% % cutoff_inds = 626-start_steps; %after omitting outliers, this is the index location of the cutoff between continuous regions
% 
% % allFreqsCut = allFreqs(good_winds,:);
% % allModesCut = allModes(good_winds,:,:);
% 
% modeStack = zeros(size(allModes,1),r*r);
% 
% for j = 1:r
%     for k = 1:r
%         modeStack(:,(j-1)*r+k) = allModes(:,k,j);
%     end
% end
% figure
% subplot(2,1,1)
% plot(real(modeStack(:,1:8)))
% subplot(2,1,2)
% plot(real(modeStack(:,9:16)))
% 
% if use_median_freqs == 0
%     save('modeSeries_slower_recursion.mat','modeStack','t_step');
% else
%     save('modeSeries_slower_recursion_i2.mat','modeStack','t_step');
% end

%% Split Regime Reconstruction

suppress_growth = 1; %kill positive real components of frequencies

xr_sep = cell(nComponents,1);
for j = 1:nComponents
    xr_sep{j} = zeros(size(x(:,1:nSteps)));
end

all_b = zeros(r,nSlide);
xn = zeros(nSteps,1); %track total contribution from all windows to each time step
% Convolve each windowed reconstruction with a gaussian
% Note that this will leave the beginning & end of time series prone to a
% lot of error. Best to cut off wSteps from each end before further
% analysis
recon_filter_sd = wSteps/8; %std dev of gaussian filter
recon_filter = exp(-((1 : wSteps) - (wSteps+1)/2).^2/recon_filter_sd^2);
save('recon_gaussian_filter_slower_recursion.mat','recon_filter','recon_filter_sd');
for k = 1:nSlide
    w = mr_res{k}.w;
    b = mr_res{k}.b;
    all_b(:,k) = b;
    Omega = mr_res{k}.Omega;
    if suppress_growth == 1
        Omega(real(Omega) > 0) = sqrt(-1) * imag(Omega(real(Omega) > 0));
    end
    om_class = mr_res{k}.om_class;
    t = mr_res{k}.t;
    c = mr_res{k}.c;
    t_start = mr_res{k}.t_start;
    tShift = t-t(1); %compute each segment of xr starting at "t = 0"
%     t_nudge = 5;
    xr_sep_window = cell(nComponents,1);
    for j = 1:nComponents
        xr_sep_window{j} = w(:, om_class == j)*diag(b(om_class == j))*exp(Omega(om_class == j)*(t-t_start));
        if j == 1 % constant shift gets put in LF recon
            xr_sep_window{j} = xr_sep_window{j} + c; 
        end
        xr_sep_window{j} = xr_sep_window{j}.*repmat(recon_filter,nVars,1);
        xr_sep{j}(:,(k-1)*stepSize+1:(k-1)*stepSize+wSteps) = xr_sep{j}(:,(k-1)*stepSize+1:(k-1)*stepSize+wSteps) + xr_sep_window{j};
    end
    
    xn((k-1)*stepSize+1:(k-1)*stepSize+wSteps) = xn((k-1)*stepSize+1:(k-1)*stepSize+wSteps) + recon_filter.';
end
for j = 1:nComponents
    xr_sep{j} = xr_sep{j}./repmat(xn.',nVars,1);
    if j == 1
        xr_sep{j} = xr_sep{j} + detrend_coeff*T; %retrend
    end
end

tspan = TimeSpan(1:nSteps);

% figure
% plot(all_b.')
% title('b values')

nanCols = isnan(vertcat(xr_sep{:}));
nanCols = sum(nanCols,1) ~= 0;


for j = 1:nComponents
    xr_sep{j} = real(xr_sep{j}(:,~nanCols));
end
tspan = tspan(~nanCols);

save('mwDMD_sep_recon_slower_recursion.mat','xr_sep','tspan','nComponents','suppress_growth');

%% Plot Separated Reconstruction
figure
subplot(nComponents+1,1,1)
plot(tspan,x(:,1:length(tspan)),'k')
% plot(tspan,x_trended(:,1:length(tspan)),'k')
xr_sum = zeros(size(x(:,1:length(tspan))));
title('Input Data')
for j = 1:nComponents
    subplot(nComponents+1,1,j+1)
    plot(tspan,xr_sep{j})
    xr_sum = xr_sum + xr_sep{j};
    title(['Component ' num2str(j) ' Reconstruction'])
end
subplot(nComponents+1,1,1)
hold on
plot(tspan,xr_sum,'b','LineWidth',1.5)

%% SVD On Reconstructions
U_sep = cell(nComponents,1);
S_sep = U_sep;
V_sep = U_sep;
r_sep = [4 2 2]; %truncation ranks for each component
figure
for j = 1:nComponents
    [U_sep{j},S_sep{j},V_sep{j}] = svd(xr_sep{j},'econ');
    subplot(1,nComponents,j)
    plot(cumsum(diag(S_sep{j}))/sum(diag(S_sep{j})),'*-','LineWidth',2)
    hold on
    plot([r_sep(j) r_sep(j)],ylim,'k:')
    title(['SVD Spectrum: Component #' num2str(j)])
    U_sep{j} = U_sep{j}(:,1:r_sep(j));
    S_sep{j} = S_sep{j}(1:r_sep(j),1:r_sep(j));
    V_sep{j} = V_sep{j}(:,1:r_sep(j));
end

figure
subplot(nComponents+1,1,1)
plot(TimeSpan(1:nSteps),x(:,1:nSteps))
title('Input Data')
for j = 1:nComponents
    subplot(nComponents+1,1,j+1)
    plot(tspan,V_sep{j})
    title(['Component ' num2str(j) ' Reconstruction: Top ' num2str(r_sep(j)) ' Modes'])
end
