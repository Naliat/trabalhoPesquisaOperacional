## Link das apresentações 01: https://drive.google.com/drive/folders/1ZqL5MdA_Y1HO547LbfR5RGJldDPoTCyx?usp=sharing

---

## Como Executar o Projeto no Ubuntu

### 1. Clonar ou Abrir a Pasta no VS Code
Abra o terminal do seu Ubuntu (`Ctrl + Alt + T`) ou o VS Code e certifique-se de estar dentro do diretório raiz do projeto:
```bash
cd /caminho/para/a/pasta/Trabalho_PO_01
```

### 2. Inicializar o Ambiente Virtual e Instalar as Dependências
Abra o terminal integrado do VS Code e inicie o interpretador do Julia:
```bash
julia
```

Dentro do prompt do Julia (`julia>`), entre no gerenciador de pacotes pressionando a tecla **`]`** e ative o ambiente local baseado nos arquivos `.toml` movidos:
```julia
(@v1.13) pkg> activate .
(Trabalho_PO_01) pkg> instantiate
```
*O comando `instantiate` lerá o arquivo `Project.toml` e vinculará automaticamente o JuMP, GLPK, Plots e demais dependências ao cache global do seu sistema de forma instantânea.*

Para retornar ao prompt normal de execução, pressione a tecla **`Backspace`**:
```julia
(Trabalho_PO_01) pkg> [Backspace]
julia> 
```

### 3. Gerar as Instâncias Geométricas de Teste
Para fabricar as 10 matrizes de custos euclidianas (incluindo as anomalias matematicamente incorretas e os grafos válidos com **tamanho de 50 nós**), execute:
```julia
julia> include("gerar_instancias.jl")
```
*Uma pasta chamada `instancias/` será criada contendo todos os arquivos `.txt` estruturados.*

### 4. Executar o Pipeline Mestre e Gerar os Mapas Rastreáveis
Para rodar a leitura automatizada, resolver o modelo inteiro via GLPK em lote, validar o fluxo e plotar as rotas em degradê colorido, execute:
```julia
julia> include("rodar_instancias.jl")
```
---