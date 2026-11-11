import sys
import os,json,numpy as np,torch,coremltools as ct
from pathlib import Path
from transformers import Wav2Vec2ForSequenceClassification
from coremltools.optimize.coreml import OptimizationConfig,OpLinearQuantizerConfig,linear_quantize_weights
torch.set_num_threads(2)
root=Path(sys.argv[1]).resolve()
model=Wav2Vec2ForSequenceClassification.from_pretrained(root/'wav-source',local_files_only=True,attn_implementation='eager').eval()
class Wrapper(torch.nn.Module):
    def __init__(self,model):
        super().__init__();self.model=model
    def forward(self,audio):
        normalized=(audio-audio.mean(dim=-1,keepdim=True))/torch.sqrt(audio.var(dim=-1,keepdim=True,unbiased=False)+1e-7)
        out=self.model.wav2vec2(normalized,output_hidden_states=True,return_dict=False)
        weights=torch.nn.functional.softmax(self.model.layer_weights,dim=-1)
        hidden=torch.stack(out[2],dim=1)
        weighted=(hidden*weights.view(1,-1,1,1)).sum(dim=1)
        embedding=self.model.projector(weighted).mean(dim=1)
        logits=self.model.classifier(embedding)
        return logits,torch.softmax(logits,dim=-1),embedding
wrapper=Wrapper(model).eval()
example=torch.randn(1,48000)*.03
with torch.no_grad():
    trace=torch.jit.trace(wrapper,example,strict=False)
    print('Trace', [tuple(x.shape) for x in trace(example)],flush=True)
if (root/'Wav2VecSuperb.mlpackage').exists():
    converted=ct.models.MLModel(str(root/'Wav2VecSuperb.mlpackage'),compute_units=ct.ComputeUnit.CPU_ONLY)
else:
    converted=ct.convert(trace,convert_to='mlprogram',minimum_deployment_target=ct.target.macOS15,
        inputs=[ct.TensorType(name='audio',shape=(1,ct.RangeDim(lower_bound=8000,upper_bound=48000,default=48000)),dtype=np.float32)],
        outputs=[ct.TensorType(name='logits'),ct.TensorType(name='probs'),ct.TensorType(name='embedding')],
        compute_precision=ct.precision.FLOAT32,compute_units=ct.ComputeUnit.CPU_ONLY)
    converted=linear_quantize_weights(converted,config=OptimizationConfig(global_config=OpLinearQuantizerConfig(mode='linear_symmetric',dtype='int8'),op_type_configs={'conv':None}))
    converted.save(str(root/'Wav2VecSuperb.mlpackage'))
compiled=converted.get_compiled_model_path()
import shutil
shutil.copytree(compiled,root/'Wav2VecSuperb.mlmodelc',dirs_exist_ok=True)
with torch.no_grad():
    for n in [8000,24000,48000]:
        x=torch.randn(1,n)*.03
        reference=wrapper(x)
        actual=converted.predict({'audio':x.numpy()})
        errors={key:float(np.max(np.abs(actual[key]-ref.numpy()))) for key,ref in zip(['logits','probs','embedding'],reference)}
        print('Validation',n,errors,flush=True)
        assert np.isfinite(actual['embedding']).all()
        assert np.max(np.abs(actual['probs']-reference[1].numpy()))<.06
print('DONE',flush=True)
