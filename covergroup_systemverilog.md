# Covergroup no SystemVerilog

## O que é?

O `covergroup` é uma estrutura de **cobertura funcional** do SystemVerilog. Seu objetivo é rastrear automaticamente se os cenários relevantes para o seu sistema foram exercitados durante a simulação.

Ele responde à pergunta:

> *"Eu já testei todas as situações importantes ou ainda existem casos que nunca foram simulados?"*

---

## Estrutura Básica

```systemverilog
covergroup nome_do_grupo @(evento);
    coverpoint sinal_ou_variavel;
endgroup
```

| Elemento | Descrição |
|---|---|
| `covergroup` | Declara o grupo de cobertura |
| `nome_do_grupo` | Identificador do grupo |
| `@(evento)` | Define quando a amostragem ocorre (ex: borda de clock) |
| `coverpoint` | Define qual sinal ou variável será monitorado |

---

## Coverpoints

Um covergroup pode ter **múltiplos coverpoints**, cada um monitorando um sinal diferente:

```systemverilog
covergroup cg_exemplo @(posedge clk);
    cp_dado:    coverpoint dado_entrada;
    cp_estado:  coverpoint estado_atual;
    cp_enable:  coverpoint enable;
endgroup
```

---

## Bins

Quando você declara um coverpoint, o simulador cria automaticamente **bins** — contadores que registram quantas vezes cada valor foi observado.

### Bins automáticos

```systemverilog
covergroup cg_auto @(posedge clk);
    coverpoint opcode; // bins criados automaticamente para cada valor
endgroup
```

### Bins manuais

Você pode definir bins explicitamente para agrupar valores com significado:

```systemverilog
covergroup cg_manual @(posedge clk);
    coverpoint dado {
        bins zero        = {0};
        bins pequeno     = {[1:10]};
        bins medio       = {[11:100]};
        bins grande      = {[101:255]};
        bins illegal_val = {8'hFF}; // valor que não deveria ocorrer
    }
endgroup
```

| Tipo de Bin | Uso |
|---|---|
| `bins`         | Valor ou faixa válida que deve ser coberta |
| `illegal_bins` | Valor que **não deve** ocorrer — gera erro se amostrado |
| `ignore_bins`  | Valor a ser **ignorado** na contagem de cobertura |

---

## Cross Coverage

O `cross` permite medir a cobertura da **combinação** entre dois coverpoints:

```systemverilog
covergroup cg_cross @(posedge clk);
    cp_op:  coverpoint operacao;
    cp_en:  coverpoint enable;

    cx_op_en: cross cp_op, cp_en; // todas as combinações entre os dois
endgroup
```

Isso garante que cada operação foi testada tanto com `enable` ativo quanto inativo.

---

## Instanciando e Usando o Covergroup

O covergroup precisa ser **instanciado** para funcionar:

```systemverilog
// Declaração
covergroup cg_dados @(posedge clk);
    coverpoint dado_entrada;
endgroup

// Instância
cg_dados cg_inst = new();

// Amostragem manual (quando não usa @evento)
cg_inst.sample();
```

---

## Amostragem: automática vs manual

| Modo | Como funciona |
|---|---|
| **Automático** | Usa `@(evento)` — amostra a cada ocorrência do evento |
| **Manual** | Chama `.sample()` explicitamente no momento desejado |

```systemverilog
// Automático
covergroup cg_auto @(posedge clk);
    coverpoint sinal;
endgroup

// Manual
covergroup cg_manual;
    coverpoint sinal;
endgroup

// Chamada manual no testbench
cg_manual cg_m = new();
cg_m.sample(); // você controla quando amostrar
```

---

## Exemplo Completo

```systemverilog
covergroup cg_matriz @(posedge clk);

    // Cobertura das linhas acessadas
    cp_linha: coverpoint lin_matriz {
        bins linha_zero  = {0};
        bins linhas_meio = {[1:6]};
        bins linha_max   = {7};
    }

    // Cobertura das colunas geradas
    cp_coluna: coverpoint col_matriz {
        bins coluna_zero = {0};
        bins colunas_mid = {[1:6]};
        bins coluna_max  = {7};
    }

    // Combinação linha x coluna
    cx_lin_col: cross cp_linha, cp_coluna;

endgroup
```

---

## Onde o Covergroup se encaixa na Verificação?

```
Testbench
    │
    ├──► DUV              ──► saída_DUV ────┐
    │                                        ├──► Comparador ──► Pass/Fail
    ├──► Modelo Referência ──► saída_REF ───┘
    │
    └──► Covergroup ──► Mede se os cenários relevantes foram exercitados
```

O comparador diz se o resultado está **correto**. O covergroup diz se você **testou o suficiente**.

---

## Resumo

| Conceito | Função |
|---|---|
| `covergroup` | Agrupa os pontos de cobertura |
| `coverpoint` | Define qual sinal monitorar |
| `bins` | Categoriza os valores observados |
| `cross` | Mede combinações entre coverpoints |
| `.sample()` | Dispara amostragem manual |
| `@(evento)` | Dispara amostragem automática |
