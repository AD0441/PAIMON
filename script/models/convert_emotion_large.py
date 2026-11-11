import sys,types,json,shutil
from pathlib import Path
import numpy as np,torch,coremltools as ct
from omegaconf import OmegaConf
from coremltools.optimize.coreml import OptimizationConfig,OpLinearQuantizerConfig,linear_quantize_weights

torch.set_num_threads(2)
torch.manual_seed(18)
root=Path(sys.argv[1]).resolve()
# Load the original architecture without FunASR's ASR, IO or training dependencies.
for name,path in [('funasr',None),('funasr.models',None),('funasr.models.emotion2vec',root/'upstream'),('funasr.utils',None)]:
    module=types.ModuleType(name);module.__path__=[str(path)] if path else []
    sys.modules[name]=module
register=types.ModuleType('funasr.register')
class Tables:
    def register(self,*args): return lambda cls:cls
register.tables=Tables();sys.modules[register.__name__]=register
load=types.ModuleType('funasr.utils.load_utils')
def unused_io(*a,**k): raise RuntimeError('Use the tensor wrapper, not FunASR IO.')
load.load_audio_text_image_video=unused_io;sys.modules[load.__name__]=load
amp=types.ModuleType('funasr.utils.amp')
amp.autocast=torch.cuda.amp.autocast;sys.modules[amp.__name__]=amp
from funasr.models.emotion2vec.model import Emotion2vec
from funasr.models.emotion2vec.base import get_alibi
config=OmegaConf.to_container(OmegaConf.load(root/'large-source/config.yaml'))
model=Emotion2vec(**config,vocab_size=9).eval()
checkpoint=torch.load(root/'large-source/model.pt',map_location='cpu',mmap=True,weights_only=True)['model']
weights={key.removeprefix('d2v_model.'):value for key,value in checkpoint.items()}
# The supervised checkpoint omits the pretraining-only reconstruction decoder.
# It is never called with features_only=True.
model.modality_encoders['AUDIO'].decoder=None
model.load_state_dict(weights,strict=True)
del checkpoint,weights
print('Loaded all original weights',flush=True)

class Wrapper(torch.nn.Module):
    def __init__(self,model): super().__init__();self.model=model
    def forward(self,audio):
        audio=(audio-audio.mean(dim=-1,keepdim=True))/torch.sqrt(audio.var(dim=-1,keepdim=True,unbiased=False)+1e-5)
        features=self.model(source=audio,padding_mask=None,mask=False,features_only=True,remove_extra_tokens=True)['x']
        embedding=features.mean(dim=1)
        logits=self.model.proj(embedding)
        return logits,torch.softmax(logits,dim=-1),embedding

wrapper=Wrapper(model).eval()
example=torch.randn(1,48000)*.03
with torch.no_grad(): expected=wrapper(example)
encoder=model.modality_encoders['AUDIO']
def dynamic_alibi(batch_size,time_steps,heads,dtype,device):
    return get_alibi(time_steps,heads).to(device=device,dtype=dtype).view(batch_size,heads,time_steps,time_steps)
encoder.get_alibi_bias=dynamic_alibi
with torch.no_grad():
    for a,b in zip(expected,wrapper(example)): torch.testing.assert_close(a,b,atol=1e-5,rtol=1e-5)
    trace=torch.jit.trace(wrapper,example,strict=False,check_trace=False)
print('Trace outputs', [tuple(t.shape) for t in trace(example)],flush=True)

converted=ct.convert(trace,convert_to='mlprogram',minimum_deployment_target=ct.target.macOS15,
    inputs=[ct.TensorType(name='audio',shape=(1,ct.RangeDim(lower_bound=8000,upper_bound=48000,default=48000)),dtype=np.float32)],
    outputs=[ct.TensorType(name='logits'),ct.TensorType(name='probs'),ct.TensorType(name='embedding')],
    compute_precision=ct.precision.FLOAT32,compute_units=ct.ComputeUnit.CPU_ONLY)
converted=linear_quantize_weights(converted,config=OptimizationConfig(global_config=OpLinearQuantizerConfig(mode='linear_symmetric',dtype='int8'),op_type_configs={'conv':None}))
converted.save(str(root/'EmotionLarge.mlpackage'))
shutil.copytree(converted.get_compiled_model_path(),root/'EmotionLarge.mlmodelc',dirs_exist_ok=True)
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
