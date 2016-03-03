%**************************************************************************
%* 
%* Copyright (C) 2016  Kiran Karra <kiran.karra@gmail.com>
%*
%* This program is free software: you can redistribute it and/or modify
%* it under the terms of the GNU General Public License as published by
%* the Free Software Foundation, either version 3 of the License, or
%* (at your option) any later version.
%*
%* This program is distributed in the hope that it will be useful,
%* but WITHOUT ANY WARRANTY; without even the implied warranty of
%* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
%* GNU General Public License for more details.
%*
%* You should have received a copy of the GNU General Public License
%* along with this program.  If not, see <http://www.gnu.org/licenses/>.

classdef mte < handle
    properties
        dag;        % the Directed Acyclic Graph structure.  The format of
                    % the DAG is an adjancency matrix.  Element (i,j)
                    % represents a connection from the ith random variable
                    % to the jth random variable
        N;
        D;
        discreteNodes;
        bnParams;
        X;
        uniqueVals; % the number of unique values for each discrete node
        
        DEBUG_MODE;
    end
    
    methods
        function obj = mte(X, discreteNodes, dag)
            % DAG - Constructs a HCBN object
            %  Inputs:
            %   X - a N x D matrix of the the observable data which the
            %       HCBN will model
            %   discreteNodes - an array w/ the indexes of the discrete
            %                   nodes
            %  Optional Inputs:
            %   dag - an adjacency matrix representing the DAG structure.
            %         If this is not specified, it is assumed that the user
            %         will learn the structure through an available
            %         learning algorithm
            %
            %  TODO
            %   [ ] - 
            %
            obj.DEBUG_MODE = 0;
            
            obj.N = size(X,1);
            obj.D = size(X,2);
            obj.X = X;
            obj.discreteNodes = discreteNodes;
            obj.dag = dag;
            obj.bnParams = cell(1,size(obj.dag,1));
            obj.uniqueVals = zeros(1,size(obj.dag,1));
            
            for ii=obj.discreteNodes
                obj.uniqueVals(ii) = length(unique(X(:,ii)));
            end
            
            obj.calcMteParams();
        end
        
        function [parentIdxs] = getParents(obj, node)
            %GETPARENTS - returns the indices and the names of a nodes
            %                 parents
            %
            % Inputs:
            %  node - the node index or name of the node for which the
            %         parents are desired
            %
            % Outputs:
            %  parentIdxs - a vector of the indices of all the parents of
            %               this node
            
            nodeIdx = node;
            parentIdxs = find(obj.dag(:,nodeIdx))';
        end
        
        function [] = calcMteParams(obj)
            %CALCCLGPARAMS - computes the CLG parameters for the specified
            %DAG with the data the CLG object was initialized with
            
            numNodes = size(obj.dag,1);
            for node=1:numNodes
                
                if(obj.DEBUG_MODE)
                    fprintf('Processing node %d\n', node);
                end
                
                % get the node's parents
                parentNodes = obj.getParents(node);
                
                if(isempty(parentNodes))
                    X_univariate = obj.X(:,node);
                    % estimate the univariate distribution
                    if(any(node==obj.discreteNodes))
                        % node is discrete, estimate w/ ecdf
                        M = size(X_univariate,1);
                        [F,x] = ecdf(X_univariate);
                        F = F(2:end);
                        x = x(2:end);
                        f = zeros(1,length(x));
                        idx = 1;
                        for jj=1:length(x)
                            f(idx) = sum(X_univariate==x(jj))/M;
                            idx = idx + 1;
                        end
                        empInfoObj = rvEmpiricalInfo(x,f,[]);
                        obj.bnParams{node} = empInfoObj;
                    else
                        % node is continuous, estimate as Gaussian and
                        % store paramters
                        mte_params = estMteDensity(X_univariate);
                        obj.bnParams{node} = mte_params;
                    end
                else
                    % if both the current node and its parents are discrete,
                    % then we can create a joint multinomial distribution,
                    % otherwise the parent must be discrete and the child be
                    % continuous
                    
                    % make a list of all the discrete parents indices
                    discreteParents = intersect(parentNodes, obj.discreteNodes);
                    
                    % make a list of all the continuous parents indices
                    continuousParents = setdiff(parentNodes, discreteParents);
                    
                    % if continousParents is not empty and our current node
                    % is discrete, this violates the CLG model so we throw
                    % an error
                    if(~isempty(continuousParents) && any(node==obj.discreteNodes))
                        error('CLG model must not have discrete children w/ continuous parents!');
                    else
                        % make combinations for all the parents
                        if(length(discreteParents)==1)
                            combos = 1:obj.uniqueVals(discreteParents(1));
                        elseif(length(discreteParents)==2)
                            combos = combvec(1:obj.uniqueVals(discreteParents(1)), ...
                                             1:obj.uniqueVals(discreteParents(2)));
                        elseif(length(discreteParents)==3)
                            combos = combvec(1:obj.uniqueVals(discreteParents(1)), ...
                                             1:obj.uniqueVals(discreteParents(2)), ...
                                             1:obj.uniqueVals(discreteParents(3)));
                        elseif(length(discreteParents)==4)
                            combos = combvec(1:obj.uniqueVals(discreteParents(1)), ...
                                             1:obj.uniqueVals(discreteParents(2)), ...
                                             1:obj.uniqueVals(discreteParents(3)), ...
                                             1:obj.uniqueVals(discreteParents(4)));
                        else
                            error('Figure out a better syntax to generalize this :)');
                        end
                        combos = combos';
                        
                        % for each combination, estimate the MTE parameter
                        numCombos = size(combos,1);
                        nodeBnParams = cell(1,numCombos);
                        nodeBnParamsIdx = 1;
                        for comboNum=1:numCombos
                            combo = combos(comboNum,:);
                            if(any(node==obj.discreteNodes))
                                % for each unique value, create probability
                                error('Currently unsupported :/ - need to add this functionality!');
                            else
                                % find all the data rows where this combo occurs
                                X_subset = [];
                                for ii=1:obj.N
                                    comboFound = 1;
                                    for jj=1:length(combo)
                                        if(obj.X(ii,discreteParents(jj))~=combo(jj))
                                            comboFound = 0;
                                        end
                                    end
                                    if(comboFound)
                                        X_subset = [X_subset; obj.X(ii,:)];
                                    end
                                end
                                if(~isempty(X_subset))
                                    % get all the continuous data associated with this combo
                                    continuousNodesIdxs = [node continuousParents];
                                    X_subset_continuous = zeros(size(X_subset,1),length(continuousNodesIdxs));
                                    idx = 1;
                                    for ii=continuousNodesIdxs
                                        X_subset_continuous(:,idx) = X_subset(:,ii);
                                        idx = idx + 1;
                                    end

                                    if(size(X_subset_continuous,2)==1)
                                        % estimate univariate Gaussian parameters
                                        mte_info = estMteDensity(X_subset_continuous);
                                    else
                                        % estimate the Multivariate Gaussian parameters
                                        error('Currently unsupported!');
                                    end
                                else
                                    fprintf('MTE COMBO not found!!\n');
                                    domain = 1:10;
                                    f = 0.00001*ones(1,10);
                                    mte_info = rvEmpiricalInfo(domain, f, []);
                                end
                                nodeBnParams{nodeBnParamsIdx} = mteNodeBnParam(node, combo, mte_info);
                                nodeBnParamsIdx = nodeBnParamsIdx + 1;
                            end
                        end
                        obj.bnParams{node} = nodeBnParams;
                    end
                end
            end
        end
        
        function [llVal] = dataLogLikelihood(obj, X)
            %DATALOGLIKELIHOOD - calculates the log-likelihood of the given
            %dataset to the calculated model of the data
            % Inputs:
            %  X - the dataset for which to calculate the log-likelihood
            % Outputs:
            %  llVal - the log-likelihood value
            M = size(X,1);
            llVal = 0;
            for nn=1:M
                nodeProb = 1;
                for node=1:obj.D
                    parentNodes = obj.getParents(node);
                    if(isempty(parentNodes))
                        nodeBnParam = obj.bnParams{node};
                        nodeProb = nodeProb * nodeBnParam.queryDensity(X(nn,node));
                    else
                        parentNodes = obj.getParents(node);
                        X_parent = X(nn,parentNodes);
                        % find the correct combo
                        numCombos = length(obj.bnParams{node});
                        for combo=1:numCombos
                            if(isequal(X_parent,obj.bnParams{node}{combo}.combo))
                                mte_info = obj.bnParams{node}{combo}.mte_info;
                                nodeProb = nodeProb * mte_info.queryDensity(X(nn,node));
                                break;
                            end
                        end
                    end
                end
                llVal = llVal + log(nodeProb);
            end
        end
        
    end
end