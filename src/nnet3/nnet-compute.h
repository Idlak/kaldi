// nnet3/nnet-compute.h

// Copyright   2012-2015  Johns Hopkins University (author: Daniel Povey)

// See ../../COPYING for clarification regarding multiple authors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
// THIS CODE IS PROVIDED *AS IS* BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, EITHER EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION ANY IMPLIED
// WARRANTIES OR CONDITIONS OF TITLE, FITNESS FOR A PARTICULAR PURPOSE,
// MERCHANTABLITY OR NON-INFRINGEMENT.
// See the Apache 2 License for the specific language governing permissions and
// limitations under the License.

#ifndef KALDI_NNET3_NNET_COMPUTE_H_
#define KALDI_NNET3_NNET_COMPUTE_H_

#include "nnet3/nnet-common.h"
#include "nnet3/nnet-nnet.h"
#include "nnet3/nnet-computation.h"
#include "nnet3/nnet-analyze.h"
#include "nnet3/nnet-example.h"

#include <iostream>
#include <sstream>
#include <vector>
#include <map>


namespace kaldi {
namespace nnet3 {


struct NnetComputeOptions {
  bool debug;
  NnetComputeOptions(): debug(false) { }
};


/**
  class NnetComputer is responsible for executing the computation described in the
  "computation" object.

  You call in sequence, the constructor, then AcceptInput(), then Forward(),
  then GetOutput(), then if applicable (Backward(), then if applicable
  GetInputDeriv()).
 */
class NnetComputer {
 public:
  /// Constructor.  nnet_to_update will be NULL if you are not doing
  /// model update or model-derivative computation.
  /// You must call computation.ComputeCudaIndexes()  before calling
  /// this function.
  NnetComputer(const NnetComputeOptions &options,
               const NnetComputation &computation,
               const Nnet &nnet,
               Nnet *nnet_to_update);

  /// e.g. AcceptInput ("input", input_mat).  Will crash if there is no
  /// input node with the given name.  This function is destructive of "input"
  /// as it takes it using the Swap function of CuMatrix.
  /// Must have the same number of rows as the corresponding input described
  /// in the ComputationRequest e.g. the indexes.size() in the corresponding
  /// IoSpecification.
  void AcceptInput(const std::string &input_name,
                   CuMatrix<BaseFloat> *input);

  /// This function calls AcceptInput() in turn on all the inputs in
  /// the training example.  It needs "nnet" only in order to distinguish
  /// inputs from outputs.
  void AcceptInputs(const Nnet &nnet,
                    const NnetExample &example);

  
  // Does the forward computation.
  void Forward();
  
  // e.g. GetOutput ("output").  Will crash if no such output.
  const CuMatrixBase<BaseFloat> &GetOutput(const std::string &output_name) const;

  /// e.g. AcceptOutputDeriv("output", &output_deriv_mat).
  void AcceptOutputDeriv(const std::string &output_name,
                         CuMatrix<BaseFloat> *output_deriv);
  

  // Does the backward computation.
  void Backward();

  // e.g. GetInputDeriv ("input").  Will crash if no such input derivative.
  // You may only call this if you requested this input derivative in the
  // ComputationRequest.
  const CuMatrixBase<BaseFloat> &GetInputDeriv(
      const std::string &input_name) const;
  
 private:
  const NnetComputeOptions &options_;
  const NnetComputation &computation_;
  const Nnet &nnet_;
  Nnet *nnet_to_update_;
  bool forward_done_;
  // command_attributes_ is only used if debug=true.
  std::vector<CommandAttributes> command_attributes_;
  // command_strings_ is only used if debug=true.
  std::vector<std::string> command_strings_;
  
  // The matrices used in the computation.
  std::vector<CuMatrix<BaseFloat> > matrices_;

  // executes the command in computation_.commands[command].
  void ExecuteCommand(int32 command);

  // Consolidate some code for getting input and output node locations (and
  // deriv locations, with error checking.
  int32 GetMatrixIndex(const std::string &node_name,
                       bool expect_output, bool is_deriv) const;

  CuSubMatrix<BaseFloat> GetSubMatrix(int32 submatrix_index);

  void GetPointers(int32 indexes_multi_index,
                   int32 num_cols,
                   CuArray<BaseFloat*> *pointers);
  void GetPointers(int32 indexes_multi_index,
                   int32 num_cols,                   
                   CuArray<const BaseFloat*> *pointers);

  // with check_output_deriv = false, checks we have all inputs.
  // with check_output_deriv = true, checks we have all required output-derivs.
  void CheckInputs(bool check_output_deriv) const;


  struct CommandDebugInfo {
    // sums of all matrices that this command writes.
    std::vector<BaseFloat> matrices_written_sums;
  };
  void DebugBeforeExecute(int32 command,
                          CommandDebugInfo *info) const;
  void DebugAfterExecute(int32 command,
                         const CommandDebugInfo &info) const;

  
};



} // namespace nnet3
} // namespace kaldi

#endif
