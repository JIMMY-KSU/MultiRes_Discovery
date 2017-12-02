clear; close all; clc

addpath('altmany-export_fig-9ac0917');
addpath(genpath(fullfile('..','Optimized DMD','optdmd-master')));
load('raw_data.mat');

r = size(x,1); %rank to fit w/ optdmd
imode = 1; %parameter for optdmd code
%  imode = 1, fit full data, slower
%  imode = 2, fit data projected onto first r POD modes
%      or columns of varargin{2} (should be at least r
%      columns in varargin{2})

windows = 2.^(9:0.5:14);
nLevels = length(windows);
nVars = size(x,1);
nSteps = 2^15; %truncation size of full data

stepSize = 2^6;

nSlide = floor((nSteps-windows)/stepSize);

mrw_res = cell(nLevels,max(nSlide));

for lv = 1:nLevels
    for k = 1:nSlide(lv)
        disp(lv,k);
        sampleStart = stepSize*(k-1) + 1;
        sampleSteps = sampleStart : sampleStart + windows(lv);
        xSample = x(:,sampleSteps);
        tSample = TimeSpan(sampleSteps);
        
        mrw_res{lv,k}.x = xSample;
        mrw_res{lv,k}.t = tSample;
        [w, e, b] = optdmd(xSample,tSample,r,imode);
        mrw_res{lv,k}.w = w;
        mrw_res{lv,k}.Omega = e;
        mrw_res{lv,k}.b = b;
    end
end


%% Cluster Frequencies
close all;
if exist('mrw_res','var') == 0
    load('mrw_res.mat');
end

mrw_nz = zeros(nLevels, max(nSlide)); % tracks which cells have a real run associated with them
for lv = 1:nLevels
    for k = 1:nSlide(lv)
        mrw_nz(lv,k) = 1;
    end
end

nComponents = 2;
% nBins = 64;

gmmList = cell(nLevels,1);
kMeansList = cell(nLevels,1);
for lv = 1:nLevels
% for lv = 1:1
    all_om = [];
    for k = 1:nSlide(lv)
        if mrw_nz(lv,k) == 0
            continue
        end
        Omega = mrw_res{lv,k}.Omega;
        all_om = [all_om; Omega];
    end

    all_om_sq = sort(conj(all_om) .* all_om);
    all_om_sq = all_om_sq(1:floor(0.99*length(all_om_sq))); %remove top 1% as outliers
    
    [idx,clustCents,clustSumD,clustDists] = kmeans(all_om_sq,nComponents);
    
    [~,sortInd] = sort(clustCents);
    kMeansList{lv}.idx = idx;
    kMeansList{lv}.clustCents = clustCents;
    kMeansList{lv}.clustSumD = clustSumD;
    kMeansList{lv}.clustDists = clustDists;
    kMeansList{lv}.sortInd = sortInd;

    mean_clust_dist = 0;
    for k = 1:nSlide
        if mrw_nz(lv,k) == 0
            continue
        end
        omega = mrw_res{lv,k}.Omega;
        om_sq = omega.*conj(omega);
        
        om_sq_dist_compare = abs(repmat(om_sq,1,nComponents) - repmat(clustCents.',length(om_sq),1));
        [om_sq_dist,om_sq_clust] = min(om_sq_dist_compare,[],2);
        
        om_class = sortInd(om_sq_clust);
        om_mean_dist = norm(om_sq_dist);
        mean_clust_dist = mean_clust_dist + om_mean_dist;
        mrw_res{lv,k}.om_class = om_class;
        mrw_res{lv,k}.om_post = om_mean_dist;
    end
    mean_clust_dist = mean_clust_dist/nSlide(lv);
    kMeansList{lv}.mean_clust_dist = mean_clust_dist;
end

save('mrw_res.mat', 'mrw_res');    

% 
% 
% %%
% for lv = 3
%     all_om = [];
%     for k = 1:nSlide(lv)
%         if mrw_nz(lv,k) == 0
%             continue
%         end
%         Omega = mrw_res{lv,k}.Omega;
%         all_om = [all_om; Omega];
%     end
%     all_om_sq = sort(conj(all_om) .* all_om);
%     all_om_sq = all_om_sq(1:floor(0.99*length(all_om_sq))); %remove top 1% as outliers
%     histogram(all_om_sq,64)
% end
% 
% %%
% all_dists = zeros(nLevels,1);
% for lv = 1:nLevels
%     all_dists(lv) = kMeansList{lv}.mean_clust_dist;
% end
% semilogy(windows,all_dists)

%% Plot MultiRes Results
close all;

export_result = 0;
logScale = 0;

% figure('units','pixels','Position',[0 0 1366 2*768])

% plotDims = [3 4]; %rows, columns of plot grid on screen at a given time
plotDims = [1 4]; %rows, columns of plot grid on screen at a given time
colorList = {'b','r','g','k','y'};
    
x_PoT = x(:,1:nSteps);
t_PoT = TimeSpan(1:nSteps);
%res_list: [pn, level #, nSplit, sampleSteps/nSplit]

dupShift = 0.02; %multiplier to shift duplicate values so they can be visually distinguished

nBins = 64;

for q = 1:size(res_list,1)
    figure('units','pixels','Position',[100 100 1200 400])
    j = res_list(q,2);
    pn = res_list(q,1);
    nSplit = 2^(j-1);
    sampleSteps = nSteps * primeList(pn) / 2^(downScale);
    steps_per_window = sampleSteps/nSplit;
    om_spec = zeros(nVars,sampleSteps);
    omIm_spec = zeros(nVars,sampleSteps);
    b_spec = zeros(nVars,sampleSteps);
%     scrollsubplot(plotDims(1),plotDims(2),[plotDims(2)*q-1, plotDims(2)*q]);
    subplot(plotDims(1),plotDims(2),[plotDims(2)-1, plotDims(2)]);
    plot(t_PoT,real(x_PoT),'k-') %plot ground truth
    xMax = max(max(abs(x_PoT)));
    
    ylim(1.5*[-xMax, xMax]);
    hold on
    
    all_om = [];
    
    for k = 1:nSplit
        Omega = mr_res{pn,j,k}.Omega;
        all_om = [all_om; Omega];
    end
    all_om_sq = all_om .* conj(all_om);
    subplot(plotDims(1),plotDims(2),plotDims(2)-2);
    om_hist = histogram(all_om_sq,nBins);
    mesh_pad = 10;
    bin_mesh = om_hist.BinEdges(1)-mesh_pad:0.5:om_hist.BinEdges(end)+mesh_pad;
    xlabel('|\omega|^2');
    ylabel('Count');
    hold on
    
    if isempty(gmmList{q}) == 0
        gmm = gmmList{q}.gmm;
        for g = 1:gmm.NumComponents
    %         plot(bin_mesh, 2*pi*max(om_hist.BinCounts) * gmm.ComponentProportion(g) * normpdf(bin_mesh, gmm.mu(g), gmm.Sigma(g)),'LineWidth',2)
            thisg = exp(-(bin_mesh - gmm.mu(g)).^2/(2*gmm.Sigma(g)^2));
            normFactor = max(om_hist.BinCounts)/max(gmm.ComponentProportion(g) * thisg);
            plot(bin_mesh, normFactor * gmm.ComponentProportion(g) * thisg ,'Color',colorList{g},'LineWidth',2)
            hold on
        end
        title(['Fit Confidence: ' num2str(gmmList{q}.fit_conf)])
    end

    
    for k = 1:nSplit
        w = mr_res{pn,j,k}.w;
%         e = mr_res{pn,j,k}.e;
        b = mr_res{pn,j,k}.b;
        Omega = mr_res{pn,j,k}.Omega;
        if isempty(gmmList{q}) == 0
            om_class = mr_res{pn,j,k}.om_class;
        end
        t = mr_res{pn,j,k}.t;
        tShift = t-t(1); %compute each segment of xr starting at "t = 0"
        t_nudge = 5;
        
        rankDefFlag = 0;
        for bi = 1:length(b)
            if b(bi) == 0
                w(:,bi) = zeros(size(w,1),1);
                rankDefFlag = 1;
            end
        end
        
        % Plot |omega|^2 spectrum
        om_sq = conj(Omega).*Omega;
        for oi = 1:length(om_sq)
            for oj = oi:length(om_sq)
                if (abs(om_sq(oi)-om_sq(oj))/((om_sq(oi)+om_sq(oj))/2)) <= dupShift && (oi ~= oj)
                    om_sq(oi) = om_sq(oi)*(1-dupShift);
                    om_sq(oj) = om_sq(oj)*(1+dupShift);
                end
            end
        end
        om_window_spec = repmat(om_sq, 1, steps_per_window);
        om_spec(:,(k-1)*steps_per_window+1:k*steps_per_window) = om_window_spec;
        
        subplot(plotDims(1),plotDims(2),plotDims(2)-3);
        if isempty(gmmList{q}) == 0 %plot clustered frequencies if GMM exists
            for g = 1:nComponents
                om_window_spec_cat = om_window_spec(om_class == g,:);
                if isempty(om_window_spec_cat) == 1
                    continue
                end
                if logScale == 1
                    semilogy(t,om_window_spec_cat,'Color',colorList{g},'LineWidth',3);
                else
                    plot(t,om_window_spec_cat,'Color',colorList{g},'LineWidth',3);
                end
                hold on
            end
        else %if there weren't enough data points to train GMM, just plot spectrum
            if logScale == 1
                semilogy(t,om_window_spec,'LineWidth',3);
            else
                plot(t,om_window_spec,'LineWidth',3);
            end
        end
%         p_om_sq = semilogy(t,om_window_spec,'LineWidth',3);
%         title(['Frequency Spectrum for ' num2str(steps_per_window) '-Step Window']);
        xlabel('t')
        xlim([t_PoT(1) t_PoT(end)]);
        ylabel('| \omega |^2')
        hold on
        
%         % Plot |Im[omega]| spectrum
%         omIm = abs(imag(Omega));
%         for oi = 1:length(omIm)
%             for oj = oi:length(omIm)
%                 if (abs(omIm(oi)-omIm(oj))/((omIm(oi)+omIm(oj))/2)) <= dupShift && (oi ~= oj)
%                     omIm(oi) = omIm(oi)*(1-dupShift);
%                     omIm(oj) = omIm(oj)*(1+dupShift);
%                 end
%             end
%         end
%         omIm_window_spec = repmat(omIm, 1, steps_per_window);
%         omIm_spec(:,(k-1)*steps_per_window+1:k*steps_per_window) = omIm_window_spec;
%         
%         subplot(plotDims(1),plotDims(2),plotDims(2)-2);
%         p_om_im = semilogy(t,omIm_window_spec,'LineWidth',3);
% %         title(['Frequency Spectrum for ' num2str(steps_per_window) '-Step Window']);
%         xlabel('t')
%         xlim([t_PoT(1) t_PoT(end)]);
%         ylabel('|Im[omega]|')
%         hold on

%         if j ~=nLevels
%             set(gca,'XTick',[])
%         end
        
      
        
%         if j ~=nLevels
%             set(gca,'XTick',[])
%         end
        
%         xr_window = zeros(nVars,steps_per_window);
%         for m = 1:nVars
%             xr_window = xr_window + Phi(:,m) * exp(w(m)*tShift) * b(m);
%         end
        
%         xr_window = w*diag(b)*exp(Omega*tShift);
        xr_window = w*diag(b)*exp(Omega*t);

        
%         scrollsubplot(plotDims(1),plotDims(2),plotDims(2)*q-1:plotDims(2)*q);
        subplot(plotDims(1),plotDims(2),plotDims(2)-1:plotDims(2));
        if rankDefFlag == 0
            p_xr = plot(t,real(xr_window),'LineWidth',2);
        else
            p_xr = plot(t,real(xr_window),'-.','LineWidth',1);
        end
        title([num2str(steps_per_window) '-Step Window (Frequencies ~' num2str(1/(steps_per_window*(t(2)-t(1)))) ' Hz)']);
        xlabel('t')
        xlim([t_PoT(1) t_PoT(end)]);
        ylabel('Re[x]')
        hold on

%         if j ~=nLevels
%             set(gca,'XTick',[])
%         end

% %         b = b ./ xr_window(:,1); %normalize so weights are as though the window starts at t=0
%         b_sq = conj(b).*b;
%         b_window_spec = repmat(b_sq, 1, steps_per_window);
% %         scrollsubplot(plotDims(1),plotDims(2),plotDims(2)*q-2);
%         subplot(plotDims(1),plotDims(2),plotDims(2)-2);
%         plot(t,b_window_spec,'LineWidth',2);
% %         title(['Weights for ' num2str(steps_per_window) '-Step Window']);
%         xlabel('t')
%         xlim([t_PoT(1) t_PoT(end)]);
%         ylim auto;
%         ylabel('|b|^2')
%         hold on
    end
    for k = 1:nSplit %plot dotted lines between time splits
        t = mr_res{pn,j,k}.t;
%         scrollsubplot(plotDims(1),plotDims(2),plotDims(2)*q-3);
        subplot(plotDims(1),plotDims(2),plotDims(2)-3);
    	plot([t(end) t(end)],get(gca, 'YLim'),'k:')
        hold on 
% %         scrollsubplot(plotDims(1),plotDims(2),plotDims(2)*q-2);
%         subplot(plotDims(1),plotDims(2),plotDims(2)-2);
%         plot([t(end) t(end)],get(gca, 'YLim'),'k:')
%         hold on 
%         scrollsubplot(plotDims(1),plotDims(2),plotDims(2)*q-1:plotDims(2)*q);
        subplot(plotDims(1),plotDims(2),plotDims(2)-1:plotDims(2));
        plot([t(end) t(end)],get(gca, 'YLim'),'k:')
        hold on 
    end
    if export_result == 1
        if q == 1
            export_fig 'manyres_opt' '-pdf';
%             print(gcf, '-dpdf', 'manyres_opt.pdf'); 
        else
            export_fig 'manyres_opt' '-pdf' '-append';
%             print(gcf, '-dpdf', 'manyres_opt.pdf', '-append'); 
        end
        close(gcf);
    end
end